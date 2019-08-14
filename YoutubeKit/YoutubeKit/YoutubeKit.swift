//
//  YoutubeKit.swift
//  YoutubeKit
//
//  Created by Nguyen Thanh Bình on 8/14/19.
//  Copyright © 2019 Nguyen Thanh Bình. All rights reserved.
//

import Foundation

extension URL {
    /**
     Parses a query string of an URL
     
     @return key value dictionary with each parameter as an array
     */
    func componentsForQueryString() -> [String: Any]? {
        if let query = self.query {
            return query.componentsFromQueryString()
        }
        
        // Note: find youtube ID in m.youtube.com "https://m.youtube.com/#/watch?v=1hZ98an9wjo"
        let result = absoluteString.components(separatedBy: "?")
        if result.count > 1 {
            return result.last?.componentsFromQueryString()
        }
        return nil
    }
}

extension String {
    /**
     Convenient method for decoding a html encoded string
     */
    func decodingURLFormat() -> String {
        let result = self.replacingOccurrences(of: "+", with:" ")
        return result.removingPercentEncoding!
    }
    
    /**
     Parses a query string
     
     @return key value dictionary with each parameter as an array
     */
    func componentsFromQueryString() -> [String: Any] {
        var parameters = [String: Any]()
        for keyValue in components(separatedBy: "&") {
            let keyValueArray = keyValue.components(separatedBy: "=")
            if keyValueArray.count < 2 {
                continue
            }
            let key = keyValueArray[0].decodingURLFormat()
            let value = keyValueArray[1].decodingURLFormat()
            parameters[key] = value
        }
        return parameters
    }
}

extension URL {
    var youtubeID: String? {
        let pathComponents = self.pathComponents
        guard let host = self.host else {
            return nil
        }
        let absoluteString = self.absoluteString
        if host == "youtu.be" && pathComponents.count > 1 {
            return pathComponents[1]
        } else if absoluteString.range(of: "www.youtube.com/embed") != nil && pathComponents.count > 2 {
            return pathComponents[2]
        } else if (host == "youtube.googleapis.com" ||
            self.pathComponents.first == "www.youtube.com") && pathComponents.count > 2 {
            return pathComponents[2]
        }
        return self.query?.componentsFromQueryString()["v"] as? String
    }
}

public class YoutubeKit {
    static let infoURL = "http://www.youtube.com/get_video_info?video_id="
    static var userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.4 (KHTML, like Gecko) Chrome/22.0.1229.79 Safari/537.4"
    /**
     Method for retrieving the youtube ID from a youtube URL
     
     @param youtubeURL the the complete youtube video url, either youtu.be or youtube.com
     @return string with desired youtube id
     */
    public static func getYoutubeID(fromURL youtubeURL: URL) -> String? {
        return youtubeURL.youtubeID
    }
    
    /**
     Method for retreiving a iOS supported video link
     
     @param youtubeURL the the complete youtube video url
     @return dictionary with the available formats for the selected video
     
     */
    private static func getVideo(withYoutubeID youtubeID: String) -> [String: Any]? {
        let urlString = "\(self.infoURL)\(youtubeID)"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpMethod = "GET"
        var responseData: Data?
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let group = DispatchGroup()
        group.enter()
        session.dataTask(with: request, completionHandler: { (data, _, _) -> Void in
            responseData = data
            group.leave()
        }).resume()
        _ = group.wait(timeout: DispatchTime.distantFuture)
        return self.handleVideoData(responseData)
    }
    
    private static func handleVideoData(_ data: Data?) -> [String: Any]? {
        guard let data = data, let responseString = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parts = responseString.componentsFromQueryString()
        if parts.count <= 0 {
            return nil
        }
        let videoTitle: String = parts["title"] as? String ?? ""
        guard let fmtStreamMap = parts["url_encoded_fmt_stream_map"] as? String else {
            return nil
        }
        // Live Stream
        if let _ = parts["live_playback"] {
            if let hlsvp = parts["hlsvp"] as? String {
                return [
                    "url": "\(hlsvp)",
                    "title": "\(videoTitle)",
                    "image": "\(parts["iurl"] as? String ?? "")",
                    "isStream": true
                ]
            }
        } else {
            let fmtStreamMapArray = fmtStreamMap.components(separatedBy: ",")
            for videoEncodedString in fmtStreamMapArray {
                var videoComponents = videoEncodedString.componentsFromQueryString()
                videoComponents["title"] = videoTitle
                videoComponents["isStream"] = false
                return videoComponents
            }
        }
        return nil
    }
    
    /**
     Block based method for retreiving a iOS supported video link
     
     @param url the the complete youtube video url
     @param completeBlock the block which is called on completion
     
     */
    public static func getVideo(withURL url: URL, completion: ((_ videoInfo: [String: Any]?, _ error: Error?) -> Void)?) {
        DispatchQueue(label: "get_video_youtube_queue").async {
            if let youtubeID = self.getYoutubeID(fromURL: url), let videoInfo = self.getVideo(withYoutubeID: youtubeID) {
                DispatchQueue.main.async {
                    completion?(videoInfo, nil)
                }
            } else {
                DispatchQueue.main.async {
                    completion?(nil, NSError(domain: "com.player.youtube.backgroundqueue", code: 1001, userInfo: ["error": "Invalid YouTube URL"]))
                }
            }
        }
    }
}
