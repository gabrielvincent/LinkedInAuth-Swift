# LinkedInAuth Swift

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

A library written in Swift for authenticating with LinkedIn using OAuth2.

The LinkedIn iOS SDK is broken by default. It forces the user to have the LinkedIn app installed on their device. This library abstracts the authentication flux using LinkedIn's OAuth2 API in an embeded `WKWebView` within the app.

## Installation

### Carthage

Add the following line to your Cartfile:

````ruby
github "gabrielvincent/LinkedInAuth-Swift"
````
### Usage

Make sure you have an app created in you LinkedIn developer account (https://www.linkedin.com/developers/apps). There you'll be able to get you client id, client secret and set the redirect URI.

First, create a configuration object:

````swift
let liAuthConfiguration = LinkedInAuthConfiguration(WithClientID: "YOUR_LINKEDIN_CLIENT_ID",
                                                    clientSecret: "YOUR_LINKEDIN_CLIENT_SECRET",
                                                    redirectURI: "https://your_redirect_uri.com",
                                                    scope: [.BasicProfile, .EmailAddress],
                                                    state: nil)
````

Then, use those configurations to begin the authentication flux:

````swift
LinkedInAuth.manager.authenticate(WithConfiguration: liAuthConfiguration, success: { (accessToken) in
            
    print("Did get access token: \(accessToken)")
    
    // Now you can use this access token to make API calls.
    
}) { (error) in
    
    print("Didn't get access token: \(error.localizedDescription)")
}
````

A `UIViewController` will be presented modally containing the `WKWebView` that will handle the authentication flux:

![LinkedIn authentication dialog screenshot](https://i.imgur.com/dWYw7wD.png)

### Redirect URI

This library doesn't require a working URI endpoint in order to get the authorization code returned after the user authorizes your app. The authorization code is captured by the `WKWebView` instance presenting the authentication dialog. Still, a valid URI is required by LinkedIn.
