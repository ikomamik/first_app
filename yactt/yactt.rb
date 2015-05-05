# encoding: utf-8

# �ėp�I�ȑg�����e�X�g���ڐ����c�[��
#   ruby yact.rb modelfile  # PICT�Ŏw�肷�郂�f���t�@�C�����w��
#   ruby yact.rb --help     # ���̑��̃I�v�V�����́A--help�Ŋm�F�\

Version = "00.00.03"

$debug = false

require "./YaParameters"

# �R�}���h�Ƃ��ČĂ΂ꂽ���̃��[�`��
def  main(command, argv)

  # �I�v�V�����̉��
  params = YaParameters.new(argv)
  
  # yactt�̎��s
  exec_yactt(params)
end

# ���C�u�����Ƃ��ČĂ΂ꂽ���̃��[�`��
def yactt_lib(options)
  params = YaParameters.new(nil, options)
  exec_yactt(params)
end

# Yactt�̎��s
def exec_yactt(params)
  require "pp"; pp params
  # PICT�̃p�����^���璆�ԃI�u�W�F�N�g�𐶐�
  require "./YaFrontPict"
  model = YaFrontPict.new(params)

  # �o�b�N�G���h�w��ɂ���ăe�X�g�����G���W����ݒ�
  solver = nil
  case params.options[:back_end]
  when /cit/i
    if(params.options[:pair_strength] > 1)
      # CIT-BACH�̃o�b�N�G���h��o�^
      require "./YaBackCitBach"
      solver = YaBackCitBach.new(params, model)
    else
      # ���x�P�̓T�|�[�g���Ă��Ȃ��̂Ŏ��͂ŉ��
      require "./YaBackZddOne"
      solver = YaBackZddOne.new(params, model)
    end
  when /acts/i
    # ACTS�̃o�b�N�G���h��o�^
    require "./YaBackActs"
    solver = YaBackActs.new(params, model)
  when /zdd/i
    # ZDD�̃o�b�N�G���h��o�^(����)
    require "./YaBackZdd"
    solver = YaBackZdd.new(params, model)
  else
    raise "back-end (#{params.options[:back_end]}) is invalid"
  end
  
  # ���K�`�̃e�X�g����(results��each���\�b�h������(������)�e�X�g�j
  results = solver.solve()
  
  # �t�����g�̃t�H�[�}�b�g�Ńe�X�g�o��
  results_string = model.write(results)

  # ���ʂ̃`�F�b�N
  if(params.options[:verify_results])
    verify_results(params, model, results)
  end
  
  results_string
end

# ���ʂ̃`�F�b�N
def verify_results(params, model, results)
  require "./YaVerifyResults"
  YaVerifyResults.verify(params, model, results)
end

# �o�b�N�G���h���s����stderr���t�@�C���ɏo�͐�ύX
def save_stderror
  # �W���G���[�̑ޔ�
  stderr_save = STDERR.dup
  
  filename = "./temp/stderr_#{Process.pid}.txt"
  new_fd = open(filename, "w") rescue raise("#{filename} open failed. rc: #{$?}\n")
  STDERR.reopen(new_fd)
  stderr_save
end

# �o�b�N�G���h���s����stderr�����ɖ߂�
def recover_stderr(stderr_save)
  STDERR.flush
  new_fd = STDERR.dup
  new_fd.close()
  STDERR.reopen(stderr_save)
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

# �R�}���h�Ƃ��Ď��s���ꂽ���̏���
if __FILE__ == $0
  begin
    # �R�}���h���ƈ��������C�����[�`���ɓn��
    main($0, ARGV)

    # �G���[���o���̏���
  rescue RuntimeError => ex
    $stderr.puts "yactt: " + ex.message
    exit(1)
  end
end

