# encoding: utf-8
require "pp"

# �o�b�N�G���h���o�͂����f�[�^��ZDD�Ō��؂���N���X
class YaVerifyResults
  require "./zdd/lib/zdd"
  
  # �R���X�g���N�^
  def self.verify(params, model_front, results)
    command_options = params.options
    solver_params   = model_front.solver_params # ���͂��ꂽ�p�����^
    submodels = model_front.submodels     # �T�u���f��
    strength = command_options[:strength] || 2
    
    zdd_params = {}    # ZDD�ŊǗ�����p�����^
    test_set = get_test_set(solver_params, model_front, zdd_params)
    
    zdd_results = eval(results.join("+"))
    all_combi = get_whole_combination(zdd_params, solver_params, test_set, submodels, strength)
    
    puts "** test_set"
    pp test_set.count
    #puts "** all_combi"
    #pp all_combi
    puts "** zdd_results"
    pp zdd_results.count
    
    check_results(test_set, all_combi, zdd_results, strength, model_front)
  end
  
  # ZDD�̃p�����^�ݒ�
  def self.get_test_set(solver_params, model_front, zdd_params)
    restricts = model_front.restricts
    negative_values = model_front.negative_values
    base_tests = model_front.base_tests
    
    # �p�����^��`�̃Z�b�g
    test_set  = ZDD.constant(1)
    solver_params.each do | param_name, values |
      zdd_params[param_name]  = ZDD.constant(0)
      values.each do | value_name |
        ZDD.symbol(value_name, 1)
        current_item = ZDD.itemset(value_name)
        eval("#{value_name} = current_item")
        zdd_params[param_name] += current_item
      end
      test_set *= zdd_params[param_name]
    end
    
    old_count = test_set.count
    
    # ��������̃Z�b�g
    # pp restricts
    zdd_params[:restrict] = restricts.map { | restrict |
      results = {}
      restrict.each do | key, value |
        results[key] = (value)?(eval(value)):nil 
      end
      results
    }
    pp zdd_params[:restrict]
    # �����I�Ɏw�肳�ꂽ��������ɏ]���č��ڂ��팸
    test_set = apply_restrict(zdd_params, test_set)
    
    # �l�K�e�B�u�l�ɂ�鐧��ɏ]���č��ڂ��팸
    test_set = negative_constraint(test_set, negative_values)

    # puts "count #{old_count} --> #{test_set.count}"
    
    # ��������𖞂������ׂẴe�X�g����
    test_set
  end

  # ��������ɏ]���A�e�X�g���ڂ��팸
  def self.apply_restrict(zdd_params, test)
    zdd_params[:restrict].each do | restrict |
      if(restrict[:if] && restrict[:else])
        test = test.restrict(restrict[:if]).iif(test.restrict(restrict[:then]), test.restrict(restrict[:else]))
      elsif(restrict[:if])
        pp test
        test = test.restrict(restrict[:if]).iif(test.restrict(restrict[:then]), test)
        pp test
        exit
      elsif(restrict[:uncond])
        test = test.restrict(restrict[:uncond])
      else
        raise "internal error, restrict type invalid"
      end
    end
    test
  end

  # �l�K�e�B�u�l�ɂ�鐧��ɏ]���č��ڂ��팸(�������@�̍H�v���K�v�j
  def self.negative_constraint(test_set, negative_values)
    if(negative_values.size() > 0)
      negative_condition = ZDD.constant(0)
      negative_values.each do | negative_value |
        negative_condition += ZDD.itemset(negative_value)
      end
      
      # �l�K�e�B�u�l���d�Ȃ��Ă���e�X�g���ڂ��팸
      test_set -= test_set.restrict((negative_condition * negative_condition)/2)
      
      #pp test_set
      # �Â��_���B������͏�L�̏����̂ق����x�^�[���Ǝv����...
      # negative_condition = ZDD.constant(1)
      # negative_values.each do | negative_value |
      #   negative_condition += ZDD.itemset(negative_value)
      # end
      # max_size = @params.keys.size()
      # test_set = (negative_condition *test_set).permitsym(max_size).termsLE(2)
      # test_set = (test_set == test_set)
    end
    test_set
  end

  # �I�[���y�A�̉�����
  def self.get_whole_combination(zdd_params, solver_params, test_set, submodels, strength = 2)

    # �S�̂̑g�����𓾂�
    all_combi = get_basic_combination(zdd_params, solver_params, strength)
    
    # �T�u���f���̑g������������
    submodels.each do | submodel |
      # pp submodel
      if(submodel[:strength] > strength)
        all_combi += get_basic_combination(zdd_params, submodel[:params], submodel[:strength])
      end
    end
    
    # �e���̂����A��܂��Ă�����̂��폜�i�������@�̍Č����v�j
    # pp all_combi.count
    work = all_combi.freqpatC(2)
    work -= work.permitsym(strength - 1)
    all_combi -= work
    
    # ���񍀖ڂɔ����Ă�����̂̍폜���悤�Ǝv�������A���������ł̓_��������
    # ���񍀖ڂƂ͊֌W�Ȃ����܂ō폜����Ă��܂��B
    # all_combi = apply_restrict2(all_combi)
    # pp all_combi
    # exit
    # ���\�I�ɖ��ȏ��������A���܂̂Ƃ��낱�̃A���S���Y��
    invalid_combi = ZDD.constant(0)
    all_combi.each do | term |
      if((test_set/term).count == 0)
        invalid_combi += term
      end
    end
    all_combi -= invalid_combi
    
  end

  # ���鋭�x�ł̂��ׂĂ̑g�����𓾂�(zdd���̃��C�u�������g���������j
  def self.get_basic_combination(zdd_params, solver_params, strength)
    test_combi = ZDD.constant(1)
    solver_params.each do | param_name, values |
      test_combi *= (zdd_params[param_name] + 1)
    end
    # ���鋭�x�ł̂��ׂĂ̑g����
    all_combi = test_combi.permitsym(strength) - test_combi.permitsym(strength-1)
    # puts "combi count = #{all_combi.count}"
    all_combi
  end
  
  # ���ʂ̊m�F
  def self.check_results(test_set, all_combi, zdd_results, strength, model_front)
  
    # �e�X�g��(������)�S�W���̃T�u�W���ł��邱�Ƃ̊m�F
    invalid_tests = ((test_set - zdd_results)  < 0)
    if(invalid_tests.count == 0)
      puts "== All tests are valid"
    else
      puts "== ERROR: following tests are invalid"
      model_front.write(invalid_tests.to_s.split(/\s*\+\s*/))
    end
    
    # �e�X�g���A�y�A���C�Y�̑g���������ׂĖ������Ă��邱�Ƃ̊m�F
    combi = all_combi.meet(test_set)
    combi -= combi.permitsym(strength-1)
    # �d�݂̍폜
    flat_combi = (combi == combi)
    no_combi = ((all_combi - flat_combi) > 0)
    if(no_combi.count == 0)
      puts "== The tests satisfies pairwise requirements"
    else
      puts "== ERROR: following combinations are not satisfied"
      no_combi.show
    end
  end

end

# �f�o�b�O�v�����g
def dbgpp(variable, title = nil)
  if($debug)
    puts "===#{title}===" if title
    if(String === variable)
      puts variable
    else
      pp variable
    end
  end
end

# �v���t�@�C����L���ɂ��邽�߂̂��܂��Ȃ�
module ZDD
  #def self.to_s
  #  self.name
  #end
end
