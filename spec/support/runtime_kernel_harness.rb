# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"

module RuntimeKernelHarness
  module_function

  def with_workspace(&)
    Dir.mktmpdir("runtime-kernel-workspace", &)
  end

  def write_file(workspace, relative_path, body)
    absolute_path = File.join(workspace, relative_path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, body)
  end

  def tree_digest(workspace)
    files = Dir.glob(File.join(workspace, "**", "*"), File::FNM_DOTMATCH)
               .select { |path| File.file?(path) }
               .sort

    digest = Digest::SHA256.new
    files.each do |absolute_path|
      relative_path = absolute_path.delete_prefix("#{workspace}/")
      OllamaAgent::State::TreeDigest.append_entry(digest, relative_path, File.read(absolute_path))
    end
    digest.hexdigest
  end
end
