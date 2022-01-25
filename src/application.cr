require "./error"
require "./ui_builder_helper"

require "./ide_window"
require "./project"
require "./welcome_window"

class Application
  include UiBuilderHelper

  getter! main_window : Gtk::ApplicationWindow?
  getter! header_bar : Gtk::HeaderBar?
  property? fullscreen = false

  delegate set_accels_for_action, to: @application

  @ide_wnd : IdeWindow?
  @welcome_wnd : WelcomeWindow?

  @new_tijolo_btn : Gtk::Button?
  @recent_files_btn : Gtk::MenuButton?
  @recent_files_menu : Gio::Menu?

  def initialize(@argv_files : Array(String))
    @application = Gtk::Application.new(application_id: "io.github.hugopl.Tijolo", flags: :non_unique)
    @application.activate_signal.connect(&->activate_ui)
  end

  private def activate_ui : Nil
    @main_window = main_window = Gtk::ApplicationWindow.new(application: @application)
    main_window.maximize
    setup_actions

    not_ported!
    builder = builder_for("header_bar")
    @header_bar = Gtk::HeaderBar.cast(builder["root"])
    @new_tijolo_btn = Gtk::Button.cast(builder["new_tijolo_btn"])
    @recent_files_btn = Gtk::MenuButton.cast(builder["recent_files_btn"])

    init_recent_files_menu
    main_window.titlebar = header_bar

    apply_css

    init_welcome unless open_project(@argv_files)
    main_window.present
  end

  def setup_actions
    # Hamburguer menu
    preferences = Gio::SimpleAction.new("preferences", nil)
    preferences.activate_signal.connect { show_preferences_dlg }
    main_window.add_action(preferences)
    about = Gio::SimpleAction.new("about", nil)
    about.activate_signal.connect { show_about_dlg }
    main_window.add_action(about)

    string = GLib::VariantType.new("s")
    open_recent = Gio::SimpleAction.new("open_recent_file", string)
    open_recent.activate_signal.connect(&->open_recent_file(GLib::Variant))
    main_window.add_action(open_recent)

    # global actions with shortcuts
    not_ported!
    config = Config.instance
    actions = {new_file:            ->new_file,
               new_file_new_split:  ->{ new_file(true) },
               open_file:           ->open_file,
               open_file_new_split: ->{ open_file(true) },
               open_project:        ->start_new_tijolo,
#                new_terminal:        ->new_terminal,
               fullscreen:          ->fullscreen}
#     actions.each do |name, closure|
#       action = Gio::SimpleAction.new(name.to_s, nil)
#       action.on_activate { closure.call }
#       main_window.add_action(action)
#
#       shortcut = config.shortcuts[name.to_s]
#       set_accels_for_action("win.#{name}", {shortcut})
#     end
  end

  private def init_recent_files_menu
    files = TijoloRC.instance.recent_files
    return if files.empty?

    reload_recent_files_menu
    @recent_files_btn.not_nil!.menu_model = recent_files_menu
  end

  private def reload_recent_files_menu
    rc = TijoloRC.instance
    recent_files_menu.remove_all # Yeah, the lazy way... just 10 itens,
    rc.recent_files.each do |file|
      label = relative_path_label(Path.new(file.to_s))
      recent_files_menu.append(label, "win.open_recent_file(#{file.to_s.inspect})")
    end
  end

  def ide : IdeWindow
    init_ide(Project.new)
  end

  def new_file(new_split = false)
    not_ported!
    # ide.create_view(nil, new_split)
  end

  def new_terminal
    ide.create_terminal
  end

  def open_file(new_split = false)
    dlg = Gtk::FileChooserDialog.new(title: "Open file", action: :open, transient_for: main_window)
    dlg.add_button("Cancel", Gtk::ResponseType::Cancel.value)
    dlg.add_button("Open", Gtk::ResponseType::Accept.value)

    ide_wnd = @ide_wnd
    dlg.current_folder = Gio::File.new_for_path(ide_wnd.project.root.to_uri.to_s) if ide_wnd && ide_wnd.project.valid?

    dlg.response_signal.connect do |response|
      if response == Gtk::ResponseType::Accept.value
        file_path = dlg.file.path
        next if file_path.nil?

        # If this zillion questions are true... the user is opening a file from another project on this project
        # So we ask if the file should be opened in another Tijolo instance.
        if ide_wnd && ide_wnd.project.valid? && !ide_wnd.project.under_project?(file_path) && Project.valid?(file_path)
          open_another_tijolo_or_file(file_path, new_split)
        else
          ide.open_file(file_path, new_split)
        end
      end
    ensure
      dlg.destroy
    end
    dlg.present
  end

  def open_recent_file(file : GLib::Variant)
    not_ported!
    # ide.open_file(Path.new(file.string)) unless file.nil?
    reload_recent_files_menu
  end

  def recent_files_menu : Gio::Menu
    @recent_files_menu ||= Gio::Menu.new
  end

  def add_recent_file(file : Path)
    TijoloRC.instance.push_recent_file(file)
    reload_recent_files_menu
  end

  def fullscreen
    if @fullscreen
      main_window.unfullscreen
    else
      main_window.fullscreen
    end
    @fullscreen = !@fullscreen
  end

  def start_new_tijolo(file : Path? = nil)
    args = file.nil? ? nil : {file.to_s}
    Process.new(Process.executable_path.to_s, args)
  end

  def show_preferences_dlg
    Config.create_config_if_needed

    not_ported!
    # ide.open_file(Config.path)
  end

  def show_about_dlg
    Gtk.show_about_dialog(parent: main_window,
      application: @application,
      copyright: "© 2020-2021 Hugo Parente Lima",
      version: "#{VERSION} (Crystal #{Crystal::VERSION})",
      program_name: "Tijolo",
      logo_icon_name: "io.github.hugopl.Tijolo",
      comments: "Lightweight, keyboard-oriented IDE for the masses",
      website: "https://github.com/hugopl/tijolo",
      website_label: "Learn more about Tijolo",
      license: Compiled::License.display,
      authors: {"Hugo Parente Lima <hugo.pl@gmail.com>"},
      artists: {"Marília Riul <mmriul@gmail.com>"})
  end

  def open_project(project_path : String) : Bool
    project = Project.new(project_path)
    return false unless project.valid?

    not_ported!
    # init_ide(project)
    true
  end

  private def open_project(files : Array(String)) : Bool
    return false if files.empty?

    pwd = Dir.current
    paths = files.map { |f| Path.new(f).expand(base: pwd) }

    project = Project.new
    paths.each do |path|
      break if project.try_load_project(path)
    end

    files_to_open = paths.reject { |path| Dir.exists?(path) }
    return false if !project.valid? && files_to_open.empty?

    not_ported!
    false
    # ide = init_ide(project)
    # files_to_open.reverse_each do |file|
    #   ide.open_file(file)
    # end
    # true
  end

  def init_welcome
    @welcome_wnd = welcome_wnd = WelcomeWindow.new(self)

    not_ported!
    # header_bar.subtitle = nil
    main_window.child = welcome_wnd.root
  end

  def destroy_welcome
    not_ported!
    # Maybe need to disconnect all signals to let GC destroy the widget
    # @welcome_wnd.try(&.destroy)
    @welcome_wnd = nil
  end

  private def init_ide(project : Project) : IdeWindow
    reuse_ide = !@ide_wnd.nil? && project.valid?
    @ide_wnd = ide_wnd = @ide_wnd || IdeWindow.new(self, project)

    not_ported!
    # header_bar.subtitle = project.valid? ? "Loading Project…" : "No Project"

    if reuse_ide
      ide_wnd.project.root = project.root
      ide_wnd.project.scan_files
    end

    child = main_window.child
    not_ported!
    # main_window.remove(child) unless child.nil?
    # main_window.add(ide_wnd.root)

    @new_tijolo_btn.not_nil!.show
    ide_wnd
  end

  def run(argv)
    @application.run(argv)
  end

  def open_another_tijolo_or_file(file : Path, new_split : Bool) : Nil
    label = relative_path_label(file)

    Gtk::MessageDialog.yes_no(message_type: :question, transient_for: main_window,
      text: "Open “#{label}” in another Tijolo instance?", secondary_text: "It belongs to another git repository.") do |res|
      if res == Gtk::ResponseType::Yes.value
        start_new_tijolo(file)
      else
        ide.open_file(file, new_split)
      end
    end
  end

  def error(exception : Exception) : Nil
    error("Error", exception.message || exception.class.name)
  end

  def error(title : String, message : String) : Nil
    Log.warn { message }
    Gtk::MessageDialog.ok(text: title, secondary_text: message, message_type: :error, transient_for: main_window) {}
  end
end
