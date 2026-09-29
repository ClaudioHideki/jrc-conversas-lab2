module JrcCrm
  module DocumentBranding
    NAME = 'JRC Conversas'.freeze
    LOGO_RELATIVE_PATH = 'public/brand-assets/logo-jrc.png'.freeze
    MUTEX = Mutex.new
    def self.logo_path
      root = defined?(Rails) && Rails.respond_to?(:root) ? Rails.root.to_s : File.expand_path('../../..', __dir__)
      File.join(root, LOGO_RELATIVE_PATH)
    end
    def self.logo
      stat = File.stat(logo_path)
      key = [logo_path, stat.size, stat.mtime.to_f]
      MUTEX.synchronize do
        if @logo_key != key
          @logo_data = CommercialPdf::Logo.load(logo_path)
          @logo_key = key
        end
        @logo_data
      end
    rescue Errno::ENOENT => e
      raise CommercialPdf::Logo::InvalidImage, "Logo oficial JRC ausente: #{e.message}"
    end
  end
end
