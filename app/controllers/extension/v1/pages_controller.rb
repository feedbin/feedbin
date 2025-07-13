module Extension
  module V1
    class PagesController < ApiController
      def create
        path = File.join(Dir.tmpdir, "pages_#{SecureRandom.hex}.html")
        File.write(path, params[:content])
        SavePageFromExtension.perform_async(current_user.id, params[:url], params[:title], path)
      end
    end
  end
end