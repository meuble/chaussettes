require 'ratatui_ruby'
require_relative '../services/logger'

module Chaussettes
  class TUIApp
    def initialize
      Logger.info('Initializing Chaussettes TUI application')
      @config_store = ConfigStore.new
      @proxy_manager = ProxyManager.new
      @ssh_tunnel = SSHTunnel.new
      @servers = @config_store.all
      @selected_index = 0
      @current_connection = nil
      @status_message = 'Ready'
      @mode = :main # :main, :form, :confirm
      @form_server = nil
      @form_buffer = {}
      @form_focus = 0
      @confirm_action = nil
      @confirm_callback = nil
      Logger.info("Chaussettes TUI initialized successfully with #{@servers.length} server(s)")
    end

    def launch
      Logger.info('Launching Chaussettes TUI')
      RatatuiRuby.run do |tui|
        loop do
          tui.draw { |frame| render(frame, tui) }

          event = tui.poll_event(timeout: 0.05)
          next unless event && !event.none?

          if event.key?
            Logger.debug("Event received: #{event.class} - #{begin
              event.code
            rescue StandardError
              'N/A'
            end}")
          end

          case @mode
          when :main
            break unless handle_main_event(event)
          when :form
            handle_form_event(event)
          when :confirm
            handle_confirm_event(event)
          end
        end
      end
      Logger.info('Chaussettes TUI shutdown complete')
    end

    private

    def render(frame, tui)
      case @mode
      when :form
        render_form(frame, tui)
      when :confirm
        render_confirm(frame, tui)
      else
        render_main(frame, tui)
      end
    end

    def render_main(frame, tui)
      main_area, status_area = tui.layout_split(
        frame.area,
        direction: :vertical,
        constraints: [tui.constraint_min(3), tui.constraint_length(3)]
      )

      render_table(frame, tui, main_area)
      render_status_bar(frame, tui, status_area)
    end

    def render_table(frame, tui, area)
      rows = @servers.map do |server|
        status = @current_connection == server ? '● Connected' : '○ Disconnected'
        [server.display_name, server.host, status]
      end

      table = tui.table(
        rows: rows,
        header: %w[Alias Host Status],
        widths: [
          tui.constraint_percentage(30),
          tui.constraint_percentage(40),
          tui.constraint_percentage(30)
        ],
        block: tui.block(
          title: ' Configured Servers ',
          title_alignment: :center,
          borders: [:all],
          border_style: { fg: 'cyan' }
        ),
        selected_row: @selected_index,
        row_highlight_style: { fg: 'black', bg: 'cyan' }
      )

      frame.render_widget(table, area)
    end

    def render_status_bar(frame, tui, area)
      help_text = '[↑↓] Navigate  [a]dd  [e]dit  [d]elete  [c]onnect  [x]disconnect  [q]uit'
      status_widget = tui.paragraph(
        text: "#{@status_message}\n#{help_text}",
        block: tui.block(borders: [:top], border_style: { fg: 'gray' }),
        style: { fg: 'white' }
      )
      frame.render_widget(status_widget, area)
    end

    def render_form(frame, tui)
      server = @form_server
      is_edit = server.id && @config_store.find(server.id)
      form_area = center_rect(frame.area, 60, 16)

      fields = [
        ['Alias (optional)', :alias_name],
        ['Host*', :host],
        ['User*', :user],
        ['SSH Port*', :ssh_port],
        ['SOCKS Port*', :socks_port],
        ['Key Path (optional)', :key_path]
      ]

      form_text = fields.map.with_index do |(label, field), idx|
        prefix = idx == @form_focus ? '> ' : '  '
        value = @form_buffer[field] || ''
        "#{prefix}#{label}: #{value}"
      end.join("\n")

      title = is_edit ? 'Edit Server' : 'Add Server'
      form_widget = tui.paragraph(
        text: "#{title}\n\n#{form_text}\n\n[Enter] Save  [Esc] Cancel  [Tab] Next  [Backspace] Delete",
        block: tui.block(
          title: " #{title} ",
          title_alignment: :center,
          borders: [:all],
          border_style: { fg: 'yellow' }
        ),
        style: { fg: 'white' }
      )

      frame.render_widget(form_widget, form_area)
    end

    def render_confirm(frame, tui)
      confirm_area = center_rect(frame.area, 50, 5)
      confirm_widget = tui.paragraph(
        text: "#{@confirm_action}\n\n[y] Yes  [n] No",
        alignment: :center,
        block: tui.block(
          title: ' Confirm ',
          title_alignment: :center,
          borders: [:all],
          border_style: { fg: 'red' }
        ),
        style: { fg: 'white' }
      )
      frame.render_widget(confirm_widget, confirm_area)
    end

    def center_rect(parent, width, height)
      x = (parent.width - width) / 2
      y = (parent.height - height) / 2
      RatatuiRuby::Layout::Rect.new(x: x, y: y, width: width, height: height)
    end

    def handle_main_event(event)
      return true unless event.key?

      code = event.code
      Logger.debug("Main mode key pressed: #{code}")

      case code
      when 'up'
        @selected_index = [@selected_index - 1, 0].max if @servers.any?
      when 'down'
        @selected_index = [@selected_index + 1, @servers.length - 1].min if @servers.any?
      when 'a'
        Logger.info('Opening add server form')
        open_add_form
      when 'e'
        if @servers[@selected_index]
          Logger.info("Opening edit server form for: #{@servers[@selected_index].display_name}")
          open_edit_form
        end
      when 'd'
        if @servers[@selected_index]
          Logger.info("Confirming delete for server: #{@servers[@selected_index].display_name}")
          confirm_delete
        end
      when 'c'
        if @servers[@selected_index] && !@current_connection
          Logger.info("Initiating connection to: #{@servers[@selected_index].display_name}")
          connect_server
        end
      when 'x'
        if @current_connection
          Logger.info('Initiating disconnect')
          disconnect_server
        end
      when 'q'
        Logger.info('Quit key pressed, exiting application')
        return false
      end

      true
    end

    def handle_form_event(event)
      return unless event.key?

      code = event.code
      fields = %i[alias_name host user ssh_port socks_port key_path]

      case code
      when 'enter'
        save_form
      when 'esc'
        close_form
      when 'tab'
        @form_focus = (@form_focus + 1) % fields.length
      when 'backspace'
        field = fields[@form_focus]
        current = @form_buffer[field] || ''
        @form_buffer[field] = current.chop unless current.empty?
      else
        # Any other key is text input
        if code && code.length == 1
          field = fields[@form_focus]
          current = @form_buffer[field] || ''
          @form_buffer[field] = current + code
        end
      end
    end

    def handle_confirm_event(event)
      return unless event.key?

      case event.code
      when 'y'
        @confirm_callback&.call
        close_confirm
      when 'n', 'esc'
        close_confirm
      end
    end

    def open_add_form
      @form_server = Server.new
      @form_buffer = {
        alias_name: '',
        host: '',
        user: '',
        ssh_port: '22',
        socks_port: '1080',
        key_path: File.expand_path('~/.ssh/id_rsa')
      }
      @form_focus = 0
      @mode = :form
    end

    def open_edit_form
      return unless @servers[@selected_index]

      server = @servers[@selected_index]
      @form_server = server
      @form_buffer = {
        alias_name: server.alias_name || '',
        host: server.host || '',
        user: server.user || '',
        ssh_port: server.ssh_port.to_s,
        socks_port: server.socks_port.to_s,
        key_path: server.key_path || ''
      }
      @form_focus = 0
      @mode = :form
    end

    def close_form
      Logger.debug('Closing form, returning to main mode')
      @mode = :main
      @form_server = nil
      @form_buffer = {}
    end

    def save_form
      Logger.info('Saving server form')
      buffer = @form_buffer
      server = @form_server

      server.alias_name = buffer[:alias_name] || ''
      server.host = buffer[:host] || ''
      server.user = buffer[:user] || ''
      server.ssh_port = (buffer[:ssh_port] || '22').to_i
      server.socks_port = (buffer[:socks_port] || '1080').to_i
      server.key_path = buffer[:key_path] || File.expand_path('~/.ssh/id_rsa')

      unless server.valid?
        error_msg = "Validation failed: #{server.errors.join(', ')}"
        Logger.warn(error_msg)
        @status_message = "Error: #{server.errors.join(', ')}"
        return
      end

      begin
        @config_store.save(server)
        @servers = @config_store.all
        close_form
        @status_message = 'Server saved'
        Logger.info("Server saved successfully: #{server.display_name}")
      rescue StandardError => e
        Logger.error("Failed to save server: #{e.message}")
        @status_message = "Error saving server: #{e.message}"
      end
    end

    def confirm_delete
      return unless @servers[@selected_index]

      server = @servers[@selected_index]
      Logger.debug("Opening delete confirmation for: #{server.display_name}")
      @confirm_action = "Delete server '#{server.display_name}'?"
      @confirm_callback = -> { execute_delete }
      @mode = :confirm
    end

    def execute_delete
      server = @servers[@selected_index]
      Logger.info("Executing delete for server: #{server.display_name}")
      @config_store.delete(server.id)
      @servers = @config_store.all
      @selected_index = [@selected_index, @servers.length - 1].min
      @status_message = 'Server deleted'
      Logger.info('Server deleted successfully')
    end

    def close_confirm
      Logger.debug('Closing confirmation dialog')
      @mode = :main
      @confirm_action = nil
      @confirm_callback = nil
    end

    def connect_server
      return unless @servers[@selected_index]
      return if @current_connection

      server = @servers[@selected_index]
      Logger.info("Connecting to server: #{server.display_name} (#{server.host}:#{server.ssh_port})")
      @status_message = "Connecting to #{server.display_name}..."

      if @ssh_tunnel.connect(server)
        Logger.info('SSH tunnel established, enabling proxy')
        @proxy_manager.enable_proxy(server.socks_port)
        @current_connection = server
        @status_message = "Connected to #{server.display_name}"
        Logger.info("Successfully connected to #{server.display_name}")
      else
        @status_message = "Failed to connect to #{server.display_name}"
        Logger.error("Failed to connect to #{server.display_name}")
      end
    rescue StandardError => e
      error_msg = "Connection error: #{e.class} - #{e.message}"
      Logger.error(error_msg)
      Logger.debug("Backtrace: #{e.backtrace&.first(3)&.join("\n")}")
      @status_message = "Error: #{e.message}"
    end

    def disconnect_server
      return unless @current_connection

      Logger.info("Disconnecting from server: #{@current_connection.display_name}")
      @status_message = 'Disconnecting...'
      @ssh_tunnel.disconnect
      @proxy_manager.disable_proxy
      @current_connection = nil
      @status_message = 'Disconnected'
      Logger.info('Disconnected successfully')
    rescue StandardError => e
      Logger.error("Error during disconnect: #{e.message}")
      @status_message = "Error disconnecting: #{e.message}"
    end
  end
end
