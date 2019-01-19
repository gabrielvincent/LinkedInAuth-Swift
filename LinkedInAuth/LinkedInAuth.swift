//
//  LinkedInAuth.swift
//  LinkedInAuth
//
//  Created by Gabriel Vincent on 17/01/19.
//  Copyright © 2019 Gabriel Vincent. All rights reserved.
//

import UIKit
import WebKit

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
    
    public init(WithClientID clientID:String, clientSecret:String, redirectURI:String, scope:[LinkedInAuthScope], state:String?) {
        
        super.init()
        
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scope = scope
        self.state = state
    }
}

public class LinkedInAuth: NSObject {
    
    fileprivate let viewController = UIViewController(nibName: nil, bundle: nil)
    fileprivate var acceptCompletionHandler:((String) -> Void)!
    fileprivate var cancelCompletionHandler:(() -> Void)!
    fileprivate var errorCompletionHandler:((Error) -> Void)!
    
    fileprivate let LinkedInAuthenticationURL_V2 = "https://www.linkedin.com/oauth/v2/authorization"
    fileprivate let LinkedInAccessTokenURL_V2  = "https://www.linkedin.com/oauth/v2/accessToken"
    
    public override init() {
        super.init()
    }
    
    // MARK: - Private functions
    
    fileprivate func scopeString(FromConfiguration configuration:LinkedInAuthConfiguration) -> String {
        
        return configuration.scope.map({$0.rawValue}).joined(separator: " ")
    }
    
    fileprivate func authenticationURL(WithConfiguration configuration:LinkedInAuthConfiguration) -> URL? {
        
        var params = "?"
        params += "response_type=" + configuration.responseType
        params += "&client_id=" + configuration.clientID
        params += "&redirect_uri=" + configuration.redirectURI
        params += "&scope=" + self.scopeString(FromConfiguration: configuration)
        
        guard let urlString = (LinkedInAuthenticationURL_V2 + params).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        
        print(urlString)
        
        let url = URL(string: urlString)
        
        return url
    }
    
    fileprivate func requestAccessToken(WithConfiguration configuration: LinkedInAuthConfiguration, authorizationCode:String, success: @escaping (String) -> Void, fail: @escaping (Error) -> Void) {
        
        print("Will request access token")
        
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
                        
                        fail(NSError(domain: "Didn't get access token", code: 2, userInfo: json))
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
    
    fileprivate func requestAuthorization(WithConfiguration configuration: LinkedInAuthConfiguration, accepted: @escaping (String) -> Void, canceled: @escaping () -> Void, error: @escaping (Error) -> Void) {
        
        guard let url = self.authenticationURL(WithConfiguration: configuration) else { return }
        
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.preferences = preferences
        
        let request = URLRequest(url: url)
        let webView = WKWebView(frame: UIScreen.main.bounds, configuration: webViewConfiguration)
        
        webView.navigationDelegate = self
        self.viewController.view.frame = UIScreen.main.bounds
        self.viewController.view.addSubview(webView)
        
        webView.load(request)
        
        self.acceptCompletionHandler = accepted
        self.cancelCompletionHandler = canceled
        self.errorCompletionHandler = error
        
        UIApplication.shared.mainWindow()?.rootViewController?.present(self.viewController, animated: true, completion: nil)
    }
    
    // MARK: - Public functions
    
    public func authenticate(WithConfiguration configuration: LinkedInAuthConfiguration, success: @escaping (String) -> Void, fail: @escaping (Error) -> Void) {
        
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

extension LinkedInAuth: WKNavigationDelegate {
    
    private func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        if let url = navigationAction.request.url, let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true), let queryItems = urlComponents.queryItems {
            
            if let code = queryItems.filter({$0.name == "code"}).first?.value {
                
                webView.stopLoading()
                self.acceptCompletionHandler(code)
                self.viewController.dismiss(animated: true, completion: nil)
                
            }
            else if let _ = queryItems.filter({$0.name == "error"}).first?.value {
                
                webView.stopLoading()
                self.cancelCompletionHandler()
                self.viewController.dismiss(animated: true, completion: nil)
            }
        }
        
        decisionHandler(.allow)
    }
}

fileprivate extension UIApplication {
    
    func mainWindow() -> UIWindow? {
        
        return self.windows.first
    }
}

fileprivate extension Dictionary {
    
    func joined(keyValueSeparator:String, itemsSeparator:String) -> String {
        
        var string = ""
        
        for key in self.keys {
            
            let stringKey = key as! String
            let value = self[key] as! String
            
            string += stringKey + keyValueSeparator + value
            string += itemsSeparator
        }
        
        string.removeLast()
        
        return string
    }
}
