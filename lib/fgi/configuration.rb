# @author Matthieu Gourvénec <matthieu.gourvenec@gmail.com>
module Fgi
  class Configuration
    class << self
      include HttpRequests

      # Launch the process to create the fresh project fgi config file
      def new_config
        puts '####################################################################'
        puts '##          Welcome to Fast Gitlab Issues configuration           ##'
        puts "####################################################################\n\n"

        # -------------------------- #
        #          CHECKERS          #
        # -------------------------- #

        git_directory?
        already_configured?

        # -------------------------- #
        #        INITIALIZERS        #
        # -------------------------- #


        # The hash that will contain the project's fgi configuration to save as yml
        # It will contain :
        #    :url
        #    :routes
        #    :project_id
        #    :project_slug
        config                     = {}

        config[:git_service_class] = define_git_service
        config[:url]               = save_git_url

        # Instanciation of the Git service class
        git_service                = config[:git_service_class].new(config)
        config[:git_service]       = git_service.to_sym
        user_token                 = save_user_token(git_service)
        project_name_and_id        = define_project_name_and_id(git_service, user_token)
        config                     = config.merge(project_name_and_id)

        # -------------------------- #
        #          CREATORS          #
        # -------------------------- #

        create_user_config_file(config[:git_service], user_token)
        create_fgi_config_file(config)
      end

      private

      # Check if we are in a git repository. Exit FGI if not.
      def git_directory?
        unless Dir.exists?('.git')
          puts 'You are not in a git project repository.'
          exit!
        end
      end

      # Check if FGI has already been configured. Exit FGI if not.
      def already_configured?
        if File.exists?('.config.fgi.yml')
          puts 'There is already a FGI config on this project.'
          exit!
        end
      end

      # Ask the user to shoose the project's Git service
      # @return [Class] the project's Git service class
      def define_git_service
        puts "\nPlease insert the number of the used Git service :"
        puts '--------------------------------------------------'

        # Get the list of the Git service for which we provide FGI at the moment
        git_services = Fgi::GitService.services
        # Display theses services to let the user choose the project's one
        git_services.each_with_index do |service, index|
          puts "#{index+1} : #{service.capitalize}"
        end
        puts "... More soon ..."

        begin
          input = STDIN.gets.chomp
          exit! if input == 'quit'
          # Convert the string input to an integer
          input = input.to_i
          # If the input isn't out of range...
          if (1..git_services.count).include?(input)
            # Set a variable with the Git service name for displays
            @git_service = git_services[input-1].capitalize
            Fgi::GitServices.const_get(@git_service)
          else
            puts "\nSorry, the option is out of range. Try again :"
            define_git_service
          end
        rescue Interrupt => int
          exit!
        end
      end

      # Ask for the Git service url.
      # @return [String] the well formatted Git service URL
      def save_git_url
        puts "\nPlease enter your #{@git_service} url :"
        puts 'example: http://gitlab.example.com/'
        puts '-----------------------------------'

        begin
          input = STDIN.gets.chomp
          exit! if input == 'quit'
          # force scheme if not specified
          input = "http://#{input}" if !input.start_with?('http://', 'https://')
          # Call the entered url to know if it exist or not.
          # If not, would raise an exception
          get(url: input)
          input
        rescue Interrupt => int
          exit!
        rescue Exception => e
          puts "\nOops, seems to be a bad url. Try again or quit (quit)"
          save_git_url
        end
      end

      # Ask for the user for his Git service token
      # @return [String] the user Git service token
      def save_user_token(git_service)
        puts "\nPlease enter your #{git_service.to_s} token :"
        puts '(use `fgi --help` to check how to get your token)'
        puts '-------------------------------------------------'

        begin
          input = STDIN.gets.chomp
          exit! if input == 'quit'
          response = get(url: git_service.routes[:projects], headers: { git_service.token_header => input })
          if response[:status] == '200'
            input
          else
            puts "\nOops, seems to be an invalid token. Try again or quit (quit) :"
            save_user_token(git_service)
          end
        rescue Interrupt => int
          exit!
        end
      end

      # Ask the user to search for the project and to select the correct one.
      # @return [Hash<String>] the hash which contain the project's slugname and id
      def define_project_name_and_id(git_service, user_token)
        puts "\nPlease enter the name of the current project :"
        puts '----------------------------------------------'

        begin
          input = STDIN.gets.chomp
          exit! if input == 'quit'

          url = "#{git_service.routes[:search_projects]}#{input}"
          response = get(url: url, headers: { git_service.token_header => user_token })

          if response[:status] == '200' && !response[:body].empty?
            puts "\nFound #{response[:body].count} match(es):"
            response[:body].each_with_index do |project, index|
              puts "#{index+1} - #{project['name_with_namespace']}"
            end

            validate_project_choice(response[:body])

          else
            puts "\nOops, we couldn't find a project called #{input}. Try again or quit (quit) :"
            puts '-------------------------------------------------------------------'+('-'*input.length) # Don't be upset, i'm a perfectionist <3
            define_project_name_and_id(git_service, user_token)
          end
        rescue Interrupt => int
          exit!
        end
      end

      def validate_project_choice(response_body)
        puts "\nPlease insert the number of the current project :"
        puts '---------------------------------------------------'
        input = STDIN.gets.chomp
        exit! if input == 'quit'
        input = input.to_i
        if (1..response_body.count).include?(input)
          {
            project_slug: response_body[input - 1]['path_with_namespace'],
            project_id:   response_body[input - 1]['id']
          }
        else
          puts "\nSorry, the option is out of range. Try again :"
          validate_project_choice(response_body)
        end
      end

      def create_fgi_config_file(config)
        File.open('.config.fgi.yml', 'w') { |f| f.write config.to_yaml }

        puts "\nYou are now set to work on #{config[:project_slug]}."
        puts 'Your configuration has been saved to .config.fgi.yml, enjoy !'
        puts "\n#############################################################"
      end

      def create_user_config_file(git_service, token)
        # Shouldn't we define some access restrictions on this file ?
        File.open("#{Dir.home}/.tokens.fgi.yml", 'w') { |f| f.write({ git_service.to_sym => token }.to_yaml) }
      end

    end
  end
end
