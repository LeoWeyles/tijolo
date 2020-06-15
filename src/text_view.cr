require "./language_manager"
require "./ui_builder_helper"
require "./observable"

module TextViewListener
  def text_view_escape_pressed
  end

  def text_view_file_path_changed(view : TextView)
  end
end

class TextView
  include UiBuilderHelper

  observable_by TextViewListener

  private enum Direction
    Up
    Down
  end

  getter file_path : Path?
  getter? readonly = false
  getter label : String
  getter widget : Gtk::Widget
  getter! search_context : GtkSource::SearchContext?

  @id : String?
  @@untitled_count = -1

  @editor : GtkSource::View
  getter buffer : GtkSource::Buffer
  @file_path_label : Gtk::Label

  getter language : Language?

  Log = ::Log.for("TextView")

  delegate grab_focus, to: @editor
  delegate focus?, to: @editor

  def initialize(file_path : String? = nil)
    builder = builder_for("text_view")
    @widget = Gtk::Widget.cast(builder["root"])
    @widget.ref
    @editor = GtkSource::View.cast(builder["editor"])
    @editor.on_key_press_event(&->key_pressed(Gtk::Widget, Gdk::EventKey))

    @buffer = GtkSource::Buffer.cast(@editor.buffer)
    @line_column = Gtk::Label.cast(builder["line_column"])
    @file_path_label = Gtk::Label.cast(builder["file_path"])

    @file_path = Path.new(file_path).expand unless file_path.nil?
    @label = @file_path.nil? ? untitled_name : File.basename(@file_path.not_nil!)

    setup_editor
    update_header
  end

  private def untitled_name
    @@untitled_count += 1
    if @@untitled_count.zero?
      "Untitled"
    else
      "Untitled #{@@untitled_count}"
    end
  end

  def file_path=(file_path : Path) : Nil
    @file_path = file_path
    self.label = File.basename(file_path.not_nil!)
    notify_text_view_file_path_changed(self)
  end

  private def label=(@label : String)
    update_header
  end

  def text
    @buffer.text(@buffer.start_iter, @buffer.end_iter, false)
  end

  def text=(text)
    @buffer.set_text(text, -1)
  end

  def language=(lang_id : String)
    language = LanguageManager.find(lang_id)
    if language
      @language = language
      @buffer.language = language.gtk_language
    end
  end

  def readonly=(value)
    @readonly = value
    @editor.editable = !value
    if value
      @file_path_label.text = "#{@label} 🔒"
    else
      @file_path_label.text = "#{@label}"
    end
  end

  def modified? : Bool
    @buffer.modified
  end

  def key_pressed(_widget : Gtk::Widget, event : Gdk::EventKey)
    if event.keyval == Gdk::KEY_Escape
      notify_text_view_escape_pressed
      true
    end
    false
  end

  def id : String
    @id ||= object_id.to_s
  end

  def save
    return if @readonly

    file_path = @file_path
    if file_path.nil?
      Log.warn { "Attempt to save a file without a name" }
      return
    end
    File.write(file_path, text)
    @buffer.modified = false
  end

  private def setup_editor
    @buffer.begin_not_undoable_action

    @buffer.style_scheme = GtkSource::StyleSchemeManager.default.scheme(Config.instance.style_scheme)

    file_path = @file_path
    if file_path
      text = File.read(file_path)
      @buffer.set_text(text, -1)
      @buffer.modified = false

      @language = language = LanguageManager.guess_language(@label, mimetype(@label, text))
      @buffer.language = language.gtk_language unless language.nil?

      self.readonly = !File.writable?(file_path)
    else
      @buffer.modified = true
    end

    @buffer.connect("notify::cursor-position") { cursor_changed }
    @buffer.on_modified_changed(&->update_header(Gtk::TextBuffer))
    @buffer.place_cursor(0)
  ensure
    @buffer.end_not_undoable_action
  end

  private def update_header(_buffer = nil)
    @file_path_label.text = @buffer.modified ? "#{@label} ✱" : @label
  end

  private def mimetype(file_name, file_contents)
    contents, uncertain = Gio.content_type_guess(file_name, file_contents)
    uncertain ? nil : contents
  end

  def cursor_pos
    iter = @buffer.iter_at_offset(@buffer.cursor_position)
    {iter.line, iter.line_offset}
  end

  private def cursor_changed
    line, col = cursor_pos
    @line_column.label = "#{line + 1}:#{col + 1}"
  end

  def create_search_context(settings : GtkSource::SearchSettings)
    @search_context ||= GtkSource::SearchContext.new(@buffer, settings)
  end

  def find
    find_impl(@buffer.cursor_position, true)
  end

  def find_next
    find_impl(@buffer.cursor_position + 1, true)
  end

  def find_prev
    find_impl(@buffer.cursor_position, false)
  end

  private def find_impl(offset, forward)
    search_context = @search_context
    return if search_context.nil?

    iter = Gtk::TextIter.new.tap do |iter|
      @buffer.iter_at_offset(iter, offset)
    end

    match_start = Gtk::TextIter.new
    match_end = Gtk::TextIter.new
    found, wrapped_around = if forward
                              search_context.forward(iter, match_start, match_end)
                            else
                              search_context.backward(iter, match_start, match_end)
                            end

    if found
      @buffer.place_cursor(match_start)
      @editor.scroll_to_iter(match_start, 0.0, true, 0.0, 0.5)
      @buffer.select_range(match_start, match_end)
    end
  end

  def goto(line, column)
    iter = Gtk::TextIter.new
    @buffer.iter_at_line(iter, line)
    iter.forward_chars(column)
    @buffer.place_cursor(iter)
    @editor.scroll_to_iter(iter, 0.0, true, 0.0, 0.5)
  end

  def comment_action
    return if readonly? || @language.nil?

    @buffer.begin_user_action
    if @buffer.has_selection
      comment_selection_action
    else
      comment_current_line_action
    end
    @buffer.end_user_action
  end

  private def comment_regex
    @comment_regex ||= /\A\s*(#{Regex.escape(@language.not_nil!.line_comment)}\s?)/
  end

  private def comment_current_line_action
    iter = Gtk::TextIter.new
    @buffer.iter_at_offset(iter, @buffer.cursor_position)

    iter.line_index = 0
    end_iter = @buffer.iter_at_line_offset(iter.line, Int32::MAX)
    line = iter.text(end_iter)
    match = comment_regex.match(line)

    if match
      uncomment_line(iter, match)
    else
      iter.line_offset = line.index(/[^\s]/) || 0
      comment_line(iter)
    end
  end

  # iter should be at start of the line
  private def uncomment_line(iter, comment_match, comment_length = nil)
    end_comment_iter = Gtk::TextIter.new
    end_comment_iter.assign(iter)

    removal_offset = comment_match.begin(1) || 0
    removal_length = comment_length || comment_match.end(1).not_nil! - removal_offset

    iter.line_offset = removal_offset
    end_comment_iter.line_offset = removal_offset + removal_length
    @buffer.delete(iter, end_comment_iter)
  end

  private def comment_line(iter)
    line_comment = language.not_nil!.line_comment
    @buffer.insert(iter, "#{line_comment} ")
  end

  # This always comment lines using line comment, /* hey */ isn't supported.
  private def comment_selection_action
    start_iter, end_iter = @buffer.selection_bounds
    start_iter.line_index = 0

    lines = @buffer.lines(start_iter.line, end_iter.line)
    matches = lines.map(&.match(comment_regex))

    if matches.all? # uncoment
      comment_length = matches.map(&.not_nil![1].size).min
      matches.each do |match|
        uncomment_line(start_iter, match.not_nil!, comment_length)
        start_iter.forward_line
      end
    else # comment
      comment_offset = lines.map { |line| line.index(/[^\s]/) || 0 }.min
      lines.size.times do
        start_iter.line_offset = comment_offset
        comment_line(start_iter)
        start_iter.forward_line
      end
    end
  end

  def move_text_up_action : Nil
    return if @buffer.has_selection

    lines_to_move = 1
    # Get cursor iterators
    start_iter = @buffer.cursor_iter
    cursor_line_index = start_iter.line_index
    start_iter.line_index = 0
    end_iter = start_iter.copy
    end_iter.forward_to_after_line_end

    text = start_iter.text(end_iter)
    no_new_line = end_iter.end?
    text = "#{text}\n" if no_new_line

    @buffer.begin_user_action
    @buffer.delete(start_iter, end_iter)
    if no_new_line
      end_iter.backward_char
      @buffer.delete(end_iter, start_iter)
      start_iter.line_index = 0
    else
      start_iter.backward_lines(lines_to_move)
    end

    @buffer.insert(start_iter, text, text.bytesize)
    start_iter.backward_lines(lines_to_move)
    start_iter.line_index = cursor_line_index
    @buffer.place_cursor(start_iter)

    @buffer.end_user_action
  end

  def move_text_down_action : Nil
    return if @buffer.has_selection

    lines_to_move = 1
    # Get cursor iterators
    start_iter = @buffer.cursor_iter
    cursor_line_index = start_iter.line_index
    start_iter.line_index = 0
    end_iter = start_iter.copy
    end_iter.forward_to_after_line_end

    return if end_iter.end?

    # Move line
    text = start_iter.text(end_iter)
    @buffer.begin_user_action
    @buffer.delete(start_iter, end_iter)

    if start_iter.forward_lines(lines_to_move)
      @buffer.insert(start_iter, text, text.bytesize)
      start_iter.backward_lines(lines_to_move)
    else                             # End of file, take care if the file ends with \n or not
      start_iter.forward_to_line_end # this will end in \0
      start_iter.backward_char       # This single backward means Tijolo doesn't support file using \r\n.
      no_new_line = start_iter.char.chr != '\n'
      text = text.sub(/(.*)([\r\n])$/, "\\2\\1") if no_new_line
      start_iter.forward_char
      @buffer.insert(start_iter, text, text.bytesize)
      start_iter.backward_line unless no_new_line
    end

    start_iter.line_index = cursor_line_index
    @buffer.place_cursor(start_iter)
    @buffer.end_user_action
  end
end
