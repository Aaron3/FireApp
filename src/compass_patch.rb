# Temporary fix for https://github.com/handlino/CompassApp/issues/79
# Ref.
# https://github.com/nex3/sass/blob/stable/lib/sass/script/funcall.rb#L94
# https://github.com/nex3/sass/issues/200
module Sass::Script
  class Funcall
    def _perform(environment)
      args = @args.map {|a| a.perform(environment)}
      if fn = environment.function(@name)
        keywords = Sass::Util.map_hash(@keywords) {|k, v| [k, v.perform(environment)]}
        return perform_sass_fn(fn, args, keywords)
      end 

      ruby_name = @name.tr('-', '_')
      args = construct_ruby_args(ruby_name, args, environment)

      unless Functions.callable?(ruby_name)
        opts(to_literal(args))
      else
        opts(Functions::EvaluationContext.new(environment.options).send(ruby_name, *args))
      end 
    rescue ArgumentError => e
      # If this is a legitimate Ruby-raised argument error, re-raise it.
      # Otherwise, it's an error in the user's stylesheet, so wrap it.

      raise Sass::SyntaxError.new("#{e.message} for `#{name}'")
    end
  end
end


module Compass
  
  # for add fireapp_build_path configuration property
  module Configuration
    def self.strip_trailing_separator(*args)
      Data.strip_trailing_separator(*args)
    end
  end

  # add fireapp_build_path configuration property
  Configuration.add_configuration_property(:fireapp_build_path, nil) do
    nil
  end
 
  # add fireapp_co_path configuration property
  Configuration.add_configuration_property(:fireapp_coffeescripts_dir, nil) do
    "coffeescripts"
  end

  module Commands
    class WatchProject 

      def perform # we remove  Signal.trap("INT"), add version check on configuration.watches
        check_for_sass_files!(new_compiler_instance)
        recompile
        require "guard"
        ::Guard.start( :guardfile_contents => <<eos
                      guard 'coffeescript', :input => 'coffeescripts', :output => 'javascripts'

                      guard 'compass' do
                          watch(/^sass\\/(.*)\.s[ac]ss/)
                      end

eos
)
      end
    end
  end

  module Frameworks
    def register_directory(directory)
      loaders = [
        File.join(directory, "compass_init.rb"),
        File.join(directory, 'lib', File.basename(directory)+".rb"),
        File.join(directory, File.basename(directory)+".rb")
      ]
      loader = loaders.detect{|l| File.exists?(l)}
      registered_framework = detect_registration do
        load loader if loader # force reload file, to make sure framework registered
      end
      unless registered_framework
        register File.basename(directory), directory
      end
    end
  end

  class Logger
    def initialize(*actions)
      self.options = actions.last.is_a?(Hash) ? actions.pop : {}
      @display   = self.options[:display]
      @log_dir = self.options[:log_dir] 
      @actions = DEFAULT_ACTIONS.dup
      @actions += actions
    end

    # Record an action that has occurred
    def record(action, *arguments)
      msg = "#{action_padding(action)}#{action} #{arguments.join(' ')}"
      if App::CONFIG["notifications"].include?(action)
        App.notify( msg.strip, @display )
        @display.wake if @display
      end
      log( msg )
    end

    def emit(msg)
      log(msg)
    end

    def log(msg)
      puts msg
      if App::CONFIG["save_notification_to_file"] && @log_dir
        @logfile = open(@log_dir + '/fire_app_log.txt','a+') unless @logfile
        @logfile.puts Time.now.strftime("%Y-%m-%d %H:%M:%S") + " " + msg
        @logfile.flush
      else
        @logfile.close if @logfile
        @logfile = nil
      end
    end
  end

  class Compiler

    # Compile one Sass file
    def compile(sass_filename, css_filename)
      start_time = end_time = nil 
      css_content = logger.red do
        timed do
          engine(sass_filename, css_filename).render
        end 
      end 
      duration = options[:time] ? "(#{(css_content.__duration * 1000).round / 1000.0}s)" : ""
      write_file(css_filename, css_content, options.merge(:force => true, :extra => duration))
     
      Compass.configuration.run_stylesheet_saved(css_filename)
      
      # PATCH: write wordlist File
      sass_filename_str = sass_filename.gsub(/[^a-z0-9]/i, '_')
      File.open( File.join( App::AUTOCOMPLTETE_CACHE_DIR, sass_filename_str + "_project" ), 'w' ) do |f|
        f.write Compass.configuration.project_path
      end

      if ::Sass::Tree::MixinDefNode.mixins
        File.open( File.join( App::AUTOCOMPLTETE_CACHE_DIR, sass_filename_str + "_mixin" ), 'w' ) do |f|

          ::Sass::Tree::MixinDefNode.mixins.uniq.sort.each do |name|
            f.puts "\"#{name}\""
          end
        end
      end

      if  ::Sass::Tree::VariableNode.variables
        File.open( File.join( App::AUTOCOMPLTETE_CACHE_DIR, sass_filename_str + "_variable" ), 'w' ) do |f|
          ::Sass::Tree::VariableNode.variables.uniq.sort.each do |name|
            f.puts "\"$#{name}\""
          end
        end
      end
    end 
  end
end


default_path = File.join( java.lang.System.getProperty("user.home"), '.compass','extensions' )

if File.exists?( default_path ) 
  App.scan_library( default_path )
  Compass::Frameworks.discover( default_path ) 
end 


