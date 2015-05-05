# encoding: utf-8
require "pp"
require "tempfile"
require "kconv"

# ACTS�ɂ��o�b�N�G���h����
class YaBackActs
  
  # �R���X�g���N�^
  def initialize(params, model_front)
    @command_options = params.options
    @model_front = model_front
    @params    = model_front.solver_params # ���͂��ꂽ�p�����^
    @submodels = model_front.submodels     # �T�u���f��
    
    @acts_params = setParams(@params, @model_front)
    @acts_base = set_base_tests(@params, model_front.base_tests)
  end
  
  # ACTS�̎��s
  def solve()
    # param_path = nil
    #Tempfile.open("yact", "./temp") do |fp|
    param_path = "./temp/acts_param.txt"
    result_path = "./temp/acts_result.txt"
    File.open(param_path, "w") do |fp|
      fp.puts @acts_params
    end

    base_tests_path = nil
    if(@acts_base)
      Tempfile.open("yact", "./temp") do |fp|
        fp.puts @acts_base
        base_tests_path = fp.path
      end
    end
    
    # ACTS�̃R�}���h�t���O�̐ݒ�
    command = "java -Doutput=csv -Drandstar=on -Dchandler=solver"
    if(@command_options[:pair_strength] == 0)
      command += " -Dcombine=all"
    else
      command += " -Ddoi=#{@command_options[:pair_strength]}"
    end
    command += " -jar ACTS/acts_cmd_2.92.jar cmd #{param_path} #{result_path}"
    
    # ���s(system�R�}���h��``�ł́A�^�C���A�E�g���E���Ȃ��̂�popen�Ŏ��s)
    results = ""
    read_buf = " " * 1024
    time_limit = @command_options[:timeout] || nil # nil���͖�����
    
    cmd_io = IO.popen(command, "r")
    tool_pid = cmd_io.pid
    while(true)
      is_read = IO.select([cmd_io], [], [], time_limit)
      if(!is_read)
        Process.kill(9, tool_pid)
        raise "time out"
      end
      
      # �u���b�N����Ȃ��悤��sysread�𔭍s�BEOF�̏ꍇ�̓��[�v�𔲂���B
      result = cmd_io.sysread(1024, read_buf) rescue break
      results += result
    end
    cmd_io.close()
    results = results.kconv(Kconv::UTF8, Kconv::SJIS).split("\n")
    
    # �G���[���̏���
    if( $? != 0 || !results[2..-1])
      error_file = "acts_error.txt"
      File.open(error_file, "w") do |fp|
        fp.puts @acts_params
      end
      raise "ACTS message: #{results}\n\nACTS parameter file is #{error_file}"
    end
    
    # ���ʂ�Ԃ��B�R�����g�A��s�͍폜���A�ŏ��̂P�s�͊֌W�Ȃ��̂łQ�s�ڂ���B
    result_text = IO.read(result_path)
    results = result_text.gsub(/^\s*(?:\#.*)?$/, "").split(/\r?\n/).select{|line| line.size() > 0}
    results[1..-1].map{|result| result.gsub("p", "@p").tr(",", "*")}
  end
  
  # ACTS�̃p�����^�ݒ�
  def setParams(params, model_front)
    acts_params = ""
    restricts = model_front.restricts
    negative_values = model_front.negative_values
    
    # �V�X�e����`�̃Z�b�g
    acts_params += "[System]\n"
    acts_params += "Name: yact_parameter\n"
    
    # �p�����^��`�̃Z�b�g
    acts_params += "[Parameter]\n"
    params.each do | param_name, values |
      acts_params += "#{param_name[1..-1]} (enum) : "
      acts_params += "#{values.map{|value| value[1..-1]}.join(", ")}\n"
    end
    
    # �T�u���f���̃Z�b�g
    acts_params += "[Relation]\n" if(@submodels.size > 0)
    @submodels.each_with_index do | submodel, i |
      params = submodel[:params].keys
      acts_params += "R#{i+1} : "
      acts_params += "(#{params.map{|param| param[1..-1]}.join(", ")}, "
      acts_params += "#{submodel[:strength]})\n"
    end

    # ��������̃Z�b�g
    acts_params += "[Constraint]\n" if(restricts.size + negative_values.size> 0)
    restricts.each do | restrict |
      acts_if = convert_restrict(restrict[:if])
      acts_then = convert_restrict(restrict[:then])
      acts_else = convert_restrict(restrict[:else])
      acts_uncond = convert_restrict(restrict[:uncond])
      if(acts_if && acts_else)
        # raise "ACTS does not support ELSE operator"
        acts_params += "(#{acts_if} => #{acts_then})\n"
        acts_params += "(!#{acts_if} => #{acts_else})\n"
      elsif(acts_if)
        acts_params += "(#{acts_if} => #{acts_then})\n"
      elsif(acts_uncond)
        acts_params += "#{acts_uncond}\n"
      else
        raise "internal error, restrict type invalid"
      end
    end
    
    # �l�K�e�B�u�l�ɂ�鐧��̃Z�b�g
    acts_params += "-- Constraints of negative value\n" if(negative_values.size > 0)
    negative_values.each_with_index do | negative_value, i |
      other_values = negative_values[(i+1)..-1]
      if(other_values.size > 0)
        acts_params += "(#{convert_item(negative_value)} => "
        acts_params += "(#{other_values.map{|value| convert_false_item(value)}.join("&&")})"
        acts_params += ")\n"
      end
    end
    
    acts_params
  end

  def convert_restrict(restrict)
    return nil unless(restrict)
    new_restrict = restrict.dup
    var_hash = {}
    var_count = 0
    # �Ϙa�`����Ruby�̐��K�\���ŋ����ɉ��
    var_expr  = "@_\\d+"
    item_expr = "(?:@p\\d+_\\d+|#{var_expr})"
    pare_expr = "\\(#{item_expr}\\)"
    deny_expr = "\\-#{item_expr}"
    prod_expr = "(?:#{item_expr}\\*)+(#{item_expr})"
    sum_expr  = "(?:#{item_expr}\\+)+(#{item_expr})"
    
    while(true)
      new_restrict.gsub!(/#{pare_expr}|#{deny_expr}|#{prod_expr}|#{sum_expr}/) { | term |
        new_term = "@_#{var_count}"
        var_hash[new_term] = term
        var_count += 1
        new_term
      }
      break if(new_restrict.match(/^#{item_expr}$/))
    end
    #puts "****"
    #pp new_restrict
    #pp var_hash
    #puts "****"

    while(true)
      rc = new_restrict.gsub!(/#{var_expr}/) { | var |
        new_term = var_hash[var]
        case new_term
        when /^#{deny_expr}$/
          # raise "ACTS does not support NOT operator"
          new_term = "(!" + new_term[1..-1] + ")"
        when /^#{prod_expr}$/
          new_term = "(" + new_term.split("*").join(")&&(") + ")"
          # new_term = new_term.split("*").join("&&")
        when /^#{sum_expr}$/
          new_term = "(" + new_term.split("+").join(")||(") + ")"
          # new_term = "(" + new_term.split("+").join(")||(") + ")"
          # new_term = new_term.split("+").join("||")
        else
          # ���̑��͕ϊ�����
        end
        new_term
      }
      break unless(rc)
    end
    new_restrict.gsub!(/#{item_expr}/) { | item |
      convert_item(item)
    }
    # pp new_restrict
    new_restrict
  end

  # ACTS�̕��@�ɕϊ��i���j
  def convert_item(item)
    item.split("_")[0][1..-1] + "=" + "\"" + item[1..-1] + "\""
  end

  # ACTS�̕��@�ɕϊ��i�I���j
  def convert_false_item(item)
    item.split("_")[0][1..-1] + "!=" + "\"" + item[1..-1] + "\""
  end

  # �x�[�X�ƂȂ�e�X�g�̓���
  def set_base_tests(params, base_tests)
    if(base_tests)
      params.keys.sort.join(",") + "\n" +
      base_tests.split("+").map{|a_test| a_test.split("*").join(",")}.join("\n")
    else
      nil
    end
  end
end

