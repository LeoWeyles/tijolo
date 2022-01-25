class ImageView < View
  @image : Gtk::Image

  def initialize(file_path : Path, project_path : Path? = nil)
    @image = Gtk::Image.new_from_file(file_path.to_s)
    super(@image, file_path, project_path)
  end

  def modified? : Bool
    false
  end

  def readonly?
    true
  end

  def reload : Nil
    super
    @image.from_file = file_path.to_s
  end
end
