require 'json'
require 'digest'

hashes = {}
%w[app config db lib enterprise docker].each do |root|
  Dir.glob("/app/#{root}/**/*", File::FNM_DOTMATCH).sort.each do |path|
    next unless File.file?(path)
    bytes = File.binread(path)
    hashes[path.delete_prefix('/app/')] = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0" + bytes)
  end
end
puts JSON.generate(revision: File.read('/app/.git_sha').strip, hashes: hashes)
