import PDFKit

@objc(PdfThumbnail)
class PdfThumbnail: NSObject {
    
    func getCachesDirectory() -> URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func getOutputFilename(filePath: String, page: Int) -> String {
        let components = filePath.components(separatedBy: "/")
        var prefix: String
        if let origionalFileName = components.last {
            prefix = origionalFileName.replacingOccurrences(of: ".", with: "-")
        } else {
            prefix = "pdf"
        }
        let random = Int.random(in: 0 ..< Int.max)
        return "\(prefix)-thumbnail-\(page)-\(random).jpg"
    }

    func generatePage(pdfPage: PDFPage, filePath: String, page: Int, quality: Int) -> Dictionary<String, Any>? {
        let pageRect = pdfPage.bounds(for: .mediaBox)
        let image = pdfPage.thumbnail(of: CGSize(width: pageRect.width, height: pageRect.height), for: .mediaBox)
        let outputFile = getCachesDirectory().appendingPathComponent(getOutputFilename(filePath: filePath, page: page))
        guard let data = image.jpegData(compressionQuality: CGFloat(quality) / 100) else {
            return nil
        }
        do {
            try data.write(to: outputFile)
            return [
                "uri": outputFile.absoluteString,
                "width": Int(pageRect.width),
                "height": Int(pageRect.height),
            ]
        } catch {
            return nil
        }
    }
    
    @available(iOS 11.0, *)
    @objc(generate:withPage:withQuality:withResolver:withRejecter:)
    func generate(filePath: String, page: Int, quality: Int, resolve:@escaping RCTPromiseResolveBlock, reject:@escaping RCTPromiseRejectBlock) -> Void {
        // Try to create URL, if it fails, encode and try again
        var fileUrl: URL?
        if let url = URL(string: filePath) {
            fileUrl = url
        } else if let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                  let url = URL(string: encodedPath) {
            fileUrl = url
        }
        
        guard let fileUrl = fileUrl else {
            reject("FILE_NOT_FOUND", "File \(filePath) not found", nil)
            return
        }
        
        // Check if it's a remote URL (http/https)
        if fileUrl.scheme == "http" || fileUrl.scheme == "https" {
            // Download the file first
            let task = URLSession.shared.downloadTask(with: fileUrl) { [weak self] localURL, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    reject("DOWNLOAD_ERROR", "Failed to download PDF: \(error.localizedDescription)", error)
                    return
                }
                
                guard let localURL = localURL else {
                    reject("DOWNLOAD_ERROR", "Failed to download PDF: no local URL", nil)
                    return
                }
                
                // Process the downloaded PDF
                self.processSinglePage(localURL: localURL, filePath: filePath, page: page, quality: quality, resolve: resolve, reject: reject)
            }
            task.resume()
        } else {
            // Local file, process directly
            processSinglePage(localURL: fileUrl, filePath: filePath, page: page, quality: quality, resolve: resolve, reject: reject)
        }
    }
    
    private func processSinglePage(localURL: URL, filePath: String, page: Int, quality: Int, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard let pdfDocument = PDFDocument(url: localURL) else {
            reject("FILE_NOT_FOUND", "File \(filePath) not found or invalid PDF", nil)
            return
        }
        guard let pdfPage = pdfDocument.page(at: page) else {
            reject("INVALID_PAGE", "Page number \(page) is invalid, file has \(pdfDocument.pageCount) pages", nil)
            return
        }

        if let pageResult = generatePage(pdfPage: pdfPage, filePath: filePath, page: page, quality: quality) {
            resolve(pageResult)
        } else {
            reject("INTERNAL_ERROR", "Cannot write image data", nil)
        }
    }

    @available(iOS 11.0, *)
    @objc(generateAllPages:withQuality:withResolver:withRejecter:)
    func generateAllPages(filePath: String, quality: Int, resolve:@escaping RCTPromiseResolveBlock, reject:@escaping RCTPromiseRejectBlock) -> Void {
        // Try to create URL, if it fails, encode and try again
        var fileUrl: URL?
        if let url = URL(string: filePath) {
            fileUrl = url
        } else if let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                  let url = URL(string: encodedPath) {
            fileUrl = url
        }
        
        guard let fileUrl = fileUrl else {
            reject("FILE_NOT_FOUND", "File \(filePath) not found", nil)
            return
        }
        
        // Check if it's a remote URL (http/https)
        if fileUrl.scheme == "http" || fileUrl.scheme == "https" {
            // Download the file first
            let task = URLSession.shared.downloadTask(with: fileUrl) { [weak self] localURL, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    reject("DOWNLOAD_ERROR", "Failed to download PDF: \(error.localizedDescription)", error)
                    return
                }
                
                guard let localURL = localURL else {
                    reject("DOWNLOAD_ERROR", "Failed to download PDF: no local URL", nil)
                    return
                }
                
                // Process the downloaded PDF
                self.processAllPages(localURL: localURL, filePath: filePath, quality: quality, resolve: resolve, reject: reject)
            }
            task.resume()
        } else {
            // Local file, process directly
            processAllPages(localURL: fileUrl, filePath: filePath, quality: quality, resolve: resolve, reject: reject)
        }
    }
    
    private func processAllPages(localURL: URL, filePath: String, quality: Int, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard let pdfDocument = PDFDocument(url: localURL) else {
            reject("FILE_NOT_FOUND", "File \(filePath) not found or invalid PDF", nil)
            return
        }

        var result: [Dictionary<String, Any>] = []
        for page in 0..<pdfDocument.pageCount {
            guard let pdfPage = pdfDocument.page(at: page) else {
                reject("INVALID_PAGE", "Page number \(page) is invalid, file has \(pdfDocument.pageCount) pages", nil)
                return
            }
            if let pageResult = generatePage(pdfPage: pdfPage, filePath: filePath, page: page, quality: quality) {
                result.append(pageResult)
            } else {
                reject("INTERNAL_ERROR", "Cannot write image data", nil)
                return
            }
        }
        resolve(result)
    }
}
