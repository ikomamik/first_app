# encoding: utf-8
require "pp"
require "tempfile"
require "kconv"

# CIT-BACH�ɂ��o�b�N�G���h����
class YaBackCitBach
  
  # �R���X�g���N�^
  def initialize(params, model_front)
    @command_options = params.options
    @model_front = model_front
    @params    = model_front.solver_params # ���͂��ꂽ�p�����^
    @submodels = model_front.submodels     # �T�u���f��
    
    @cit_params = setParams(@params, @model_front)
    @cit_base = set_base_tests(@params, model_front.base_tests)
  end
  
  # CIT-BACH�̎��s
  def solve()
    param_path = nil
    Tempfile.open("yact", "./temp") do |fp|
      fp.puts @cit_params
      param_path = fp.path
    end

    base_tests_path = nil
    if(@cit_base)
      Tempfile.open("yact", "./temp") do |fp|
        fp.puts @cit_base
        base_tests_path = fp.path
      end
    end
    
    # cit�f�B���N�g���ɂ���jar��T���i�o�[�W�����ԍ����傫�����̂�I���j
    cit_jar = Dir.glob("cit/cit-bach*.jar").sort[-1]
    
    # CIT�̃R�}���h�t���O�̐ݒ�
    command = "java -jar #{cit_jar} -i #{param_path}"
    command += " -s #{base_tests_path}" if(@cit_base)
    command += " -random #{@command_options[:random_seed]}" if(@command_options[:random_seed])
    if(@command_options[:pair_strength] == 0)
      command += " -c all"
    else
      command += " -c #{@command_options[:pair_strength]}"
    end
    # puts command

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
    if(!results[0].match(/^#SUCCESS,/))
      error_file = "cit_error.txt"
      File.open(error_file, "w") do |fp|
        fp.puts @cit_params
      end
      raise "CIT-BACH message: #{results[0]}\nCIT-BACH parameter file is #{error_file}"
    end
    
    # ���ʂ�Ԃ��B�ŏ��̓�s�͊֌W�Ȃ��̂łR�s�ڂ���B
    results[2..-1].map{|result| result.tr(",", "*")}
  end
  
  # CitBach�̃p�����^�ݒ�
  def setParams(params, model_front)
    cit_params = ""
    restricts = model_front.restricts
    negative_values = model_front.negative_values
    
    # �p�����^��`�̃Z�b�g
    cit_params += "# Parameters\n"
    params.each do | param_name, values |
      cit_params += "#{param_name} (#{values.join(" ")})\n"
    end
    
    # �T�u���f���̃Z�b�g
    cit_params += "# Submodels\n" if(@submodels.size > 0)
    @submodels.each do | submodel |
      params = submodel[:params].keys
      cit_params += "{#{params.join(" ")}}\n"
      warn "yact: submodel strength is unmatch" if(params.size != submodel[:strength])
    end

    # ��������̃Z�b�g
    cit_params += "# Written constraints\n" if(restricts.size > 0)
    restricts.each do | restrict |
      cit_if = convert_restrict(restrict[:if])
      cit_then = convert_restrict(restrict[:then])
      cit_else = convert_restrict(restrict[:else])
      cit_uncond = convert_restrict(restrict[:uncond])
      if(cit_if && cit_else)
        cit_params += "(ite #{cit_if} #{cit_then} #{cit_else})\n"
      elsif(cit_if)
        cit_params += "(if  #{cit_if} #{cit_then})\n"
      elsif(cit_uncond)
        cit_params += "#{cit_uncond}\n"
      else
        raise "internal error, restrict type invalid"
      end
    end
    
    # �l�K�e�B�u�l�ɂ�鐧��̃Z�b�g
    cit_params += "# Constraints of negative value\n" if(negative_values.size > 0)
    negative_values.each_with_index do | negative_value, i |
      other_values = negative_values[(i+1)..-1]
      if(other_values.size > 0)
        cit_params += "(if #{convert_item(negative_value)} "
        if(other_values.size > 1)
          cit_params += "(and #{other_values.map{|value| convert_false_item(value)}.join(" ")})"
        else
          cit_params += convert_false_item(other_values[0])
        end
        cit_params += ")\n"
      end
    end
    
    cit_params
  end

  # ������������̕ϊ�
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
          new_term = "(not " + new_term[1..-1] + ")"
        when /^#{prod_expr}$/
          new_term = "(and " + new_term.split("*").join(" ") + ")"
        when /^#{sum_expr}$/
          new_term = "(or " + new_term.split("+").join(" ") + ")"
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

  # CIT�̕��@�ɕϊ��i�����j
  def convert_item(item)
    "(== [" + item.split("_")[0] + "] " + item + ")"
  end

  # CIT�̕��@�ɕϊ��i�����j
  def convert_false_item(item)
    "(<> [" + item.split("_")[0] + "] " + item + ")"
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

