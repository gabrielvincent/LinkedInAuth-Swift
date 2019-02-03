//
//  LinkedInAuth.swift
//  LinkedInAuth
//
//  Created by Gabriel Vincent on 17/01/19.
//  Copyright © 2019 Gabriel Vincent. All rights reserved.
//

import UIKit
import WebKit

fileprivate enum URLBuildingError: Error {
    case invalidURL(string: String?)
}

public enum LinkedInAuthScope:String {
    
    case BasicProfile = "r_basicprofile"
    case LiteProfile  = "r_liteprofile"
    case EmailAddress = "r_emailaddress"
    case MemberSocial = "w_member_social"
}

public class LinkedInAuthConfiguration:NSObject {
    
    var responseType:String = "code"
    var clientID:String!
    var clientSecret:String!
    var redirectURI:String!
    var scope:[LinkedInAuthScope]!
    var state:String?
    
    public init(WithClientID clientID:String, clientSecret:String, redirectURI:String, scope:[LinkedInAuthScope], state:String? = "code") {
        
        super.init()
        
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scope = scope
        self.state = state
    }
    
    // MARK: - Class functions
}

public class LinkedInAuth: NSObject {
    
    public static let manager = LinkedInAuth()
    
    private let webView:WKWebView
    private let viewController:UIViewController
    private var acceptCompletionHandler:((String) -> Void)!
    private var cancelCompletionHandler:(() -> Void)!
    private var errorCompletionHandler:((Error) -> Void)!
    
    private let LinkedInAuthenticationURL_V2 = "https://www.linkedin.com/oauth/v2/authorization"
    private let LinkedInAccessTokenURL_V2  = "https://www.linkedin.com/oauth/v2/accessToken"
    
    private var urlObservation:NSKeyValueObservation?
    
    private override init() {
        
        self.viewController = UIViewController(nibName: nil, bundle: nil)
        self.viewController.view.frame = UIScreen.main.bounds
        self.webView = WKWebView(frame: self.viewController.view.frame)
        
        super.init()
        
        self.viewController.view.addSubview(self.webView)
        
        self.urlObservation = self.webView.observe(\.url) { [weak self] (webView, change) in
            
            self?.webViewURLDidChange(webView)
        }
    }
    
    // MARK: - Private functions
    
    private func webViewURLDidChange(_ webView:WKWebView) {
        
        if let url = webView.url, let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true), let queryItems = urlComponents.queryItems {
            
            print("[LinkedInAuth]: Found query items. Probably being redirected.")
            
            if let code = queryItems.filter({$0.name == "code"}).first?.value {
                
                self.acceptCompletionHandler(code)
                self.viewController.dismiss(animated: true, completion: nil)
                
            }
            else if let _ = queryItems.filter({$0.name == "error"}).first?.value {
                
                self.cancelCompletionHandler()
                self.viewController.dismiss(animated: true, completion: nil)
            }
        }
    }
    
    private func authenticationURL(WithConfiguration configuration:LinkedInAuthConfiguration) throws -> URL {
        
        var params = "?"
        params += "response_type=" + configuration.responseType
        params += "&client_id=" + configuration.clientID
        params += "&redirect_uri=" + configuration.redirectURI
        params += "&scope=" + configuration.scope.asString()
        
        guard let urlString = (LinkedInAuthenticationURL_V2 + params).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            
            throw URLBuildingError.invalidURL(string: nil)
        }
        
        guard let url = URL(string: urlString) else {
            
            throw URLBuildingError.invalidURL(string: urlString)
        }
        
        return url
    }
    
    private func requestAccessToken(WithConfiguration configuration: LinkedInAuthConfiguration, authorizationCode:String, success: @escaping (String) -> Void, fail: @escaping (Error) -> Void) {
        
        print("[LinkedInAuth]: Will request access token")
        
        if let url = URL(string: LinkedInAccessTokenURL_V2) {
            
            var request = URLRequest(url: url)
            let params = [
                "grant_type": "authorization_code",
                "code": authorizationCode,
                "redirect_uri": configuration.redirectURI,
                "client_id": configuration.clientID,
                "client_secret": configuration.clientSecret
            ]
            let paramsString = params.joined(keyValueSeparator: "=", itemsSeparator: "&")
            let httpBodyData = paramsString.data(using: .utf8)
            
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = httpBodyData
            
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                
                guard data != nil, response != nil, error == nil else {
                    
                    fail(error!)
                    return
                }
                
                do {
                    
                    if let json = try JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String:Any] {
                        
                        if let accessToken = json["access_token"] as? String {
                            
                            success(accessToken)
                            return
                        }
                        
                        fail(NSError(domain: "Didn't get access token. Response data: \(json.debugDescription)", code: 2, userInfo: json))
                    }
                }
                catch let error {
                    
                    fail(error)
                    return
                }
            }
            task.resume()
        }
    }
    
    private func requestAuthorization(WithConfiguration configuration: LinkedInAuthConfiguration, accepted: @escaping (String) -> Void, canceled: @escaping () -> Void, error: @escaping (Error) -> Void) {
        
        do {
            
            let url = try self.authenticationURL(WithConfiguration: configuration)
            
            print("[LinkedInAuth]: Will request authorization from: \(url.absoluteURL)")
            
            let request = URLRequest(url: url)
            
            self.webView.load(request)
            
            self.acceptCompletionHandler = accepted
            self.cancelCompletionHandler = canceled
            self.errorCompletionHandler = error
            
            UIApplication.shared.mainWindow()?.rootViewController?.present(self.viewController, animated: true, completion: nil)
        }
        catch URLBuildingError.invalidURL(let urlString) {
            
            NSException(name: NSExceptionName("URLBuildingException"), reason: "The URL built from the provided configuration is invalid. URL string: \(String(describing: urlString))", userInfo: nil).raise()
        }
        catch {
            
            NSException(name: NSExceptionName("UnknownException"), reason: "An uknown exception was raised from LinkedInAuth requestAuthorization method", userInfo: nil).raise()
        }
    }
    
    // MARK: - Public functions
    
    public func authenticate(WithConfiguration configuration: LinkedInAuthConfiguration, success: @escaping (String) -> Void, fail: @escaping (Error) -> Void) {
        
        print("[LinkedInAuth]: Will authenticate with scope: \(configuration.scope.map({$0.rawValue}))")
        
        self.requestAuthorization(WithConfiguration: configuration, accepted: { (authorizationCode) in
            
            self.requestAccessToken(WithConfiguration: configuration, authorizationCode: authorizationCode, success: { (accessToken) in
                
                success(accessToken)
                
            }, fail: { (error) in
                
                fail(error)
            })
            
        }, canceled: {
            
            fail(NSError(domain: "User did not authorize LinkedIn", code: 1, userInfo: nil))
            
        }) { (error) in
            
            fail(error)
        }
    }
}

// MARK: - Extensions

fileprivate extension UIApplication {
    
    func mainWindow() -> UIWindow? {
        
        return self.windows.first
    }
}

fileprivate extension Dictionary {
    
    func joined(keyValueSeparator:String, itemsSeparator:String) -> String {
        
        var string = ""
        
        for key in self.keys {
            
            let keyString = key as! String
            let value = self[key] as! String
            
            if !string.isEmpty {
                
                string += itemsSeparator
            }
            
            string += "\(keyString)" + keyValueSeparator + "\(value)"
        }
        
        return string
    }
}

fileprivate extension Array where Element == LinkedInAuthScope {
    
    func asString() -> String {
        
        return self.map({$0.rawValue}).joined(separator: " ")
    }
}
