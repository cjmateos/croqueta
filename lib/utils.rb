require 'colorize'

def print_msg(msg)
  printf msg + "\n"
end

def print_inline(msg)
  printf msg
end

def print_info(msg)
  printf 'INFO'.colorize(:light_green) + ': ' + msg + "\n"
end

def print_warn(msg)
  printf 'WARN'.colorize(:light_yellow) + ': ' + msg + "\n"
end

def print_error(msg)
  printf 'ERROR'.colorize(:red) + ': ' + msg + "\n"
end

def ok
  puts 'OK'.colorize(:light_green)
end

def error
  puts 'ERROR'.colorize(:red)
end

def separator
  puts "********************************************************"
end

def yesno(prompt = 'Continue?', default = true)
  a = ''
  s = default ? '[Y/n]' : '[y/N]'
  d = default ? 'y' : 'n'
  until %w[y n].include? a
    a = ask("#{prompt} #{s} ") { |q| q.limit = 1; q.case = :downcase }
    a = d if a.length == 0
  end
  a == 'y'
end
