//
//  UIImageView+AFNetworking.swift
//  FlickrClient
//
//  Created by Igor Kolpachkov on 18.03.15.
//  Copyright (c) 2015 com.xstudio.ikolpachkov. All rights reserved.
//

import UIKit

protocol AFImageCacheProtocol:class{
    func cachedImageForRequest(request:NSURLRequest) -> UIImage?
    func cacheImage(image:UIImage, forRequest request:NSURLRequest);
}

extension UIImageView {
    private struct AssociatedKeys {
        static var SharedImageCache = "SharedImageCache"
        static var RequestImageOperation = "RequestImageOperation"
        static var URLRequestImage = "UrlRequestImage"
    }
    
    class func setSharedImageCache(cache:AFImageCacheProtocol?) {
        objc_setAssociatedObject(self, &AssociatedKeys.SharedImageCache, cache, UInt(OBJC_ASSOCIATION_COPY))
    }
    
    class func sharedImageCache() -> AFImageCacheProtocol {
        struct Static {
            static var token : dispatch_once_t = 0
            static var defaultImageCache:AFImageCache?
        }
        
        dispatch_once(&Static.token, { () -> Void in
            Static.defaultImageCache = AFImageCache()
            NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationDidReceiveMemoryWarningNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (NSNotification) -> Void in
                Static.defaultImageCache!.removeAllObjects()
            }
        })
        return objc_getAssociatedObject(self, &AssociatedKeys.SharedImageCache) as? AFImageCache ?? Static.defaultImageCache!
    }
    
    class func af_sharedImageRequestOperationQueue() -> NSOperationQueue {
        struct Static {
            static var token:dispatch_once_t = 0
            static var queue:NSOperationQueue?
        }
        
        dispatch_once(&Static.token, { () -> Void in
            Static.queue = NSOperationQueue()
            Static.queue!.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount
        })
        return Static.queue!
    }
    
    private var af_requestImageOperation:(operation:NSOperation?, request: NSURLRequest?) {
        get {
            let operation:NSOperation? = objc_getAssociatedObject(self, &AssociatedKeys.RequestImageOperation) as? NSOperation
            let request:NSURLRequest? = objc_getAssociatedObject(self, &AssociatedKeys.URLRequestImage) as? NSURLRequest
            return (operation, request)
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.RequestImageOperation, newValue.operation, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
            objc_setAssociatedObject(self, &AssociatedKeys.URLRequestImage, newValue.request, UInt(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
        }
    }
    
    func setImageWithUrl(url:NSURL, placeHolderImage:UIImage? = nil) {
        self.setImageWithUrlRequest(url, placeHolderImage: placeHolderImage, success: nil, failure: nil)
    }
    
    func setImageWithUrlRequest(url:NSURL, placeHolderImage:UIImage? = nil,
        success:((request:NSURLRequest?, response:NSURLResponse?, image:UIImage) -> Void)?,
        failure:((request:NSURLRequest?, response:NSURLResponse?, error:NSError?) -> Void)?)
    {
        let requestMutable:NSMutableURLRequest = NSMutableURLRequest(URL: url)
        requestMutable.addValue("image/*", forHTTPHeaderField: "Accept")
        let request: NSURLRequest = requestMutable
        
        self.cancelImageRequestOperation()
        
        if let cachedImage = UIImageView.sharedImageCache().cachedImageForRequest(request) {
            if success != nil {
                success!(request: nil, response:nil, image: cachedImage)
            }
            else {
                self.image = cachedImage
            }
            
            return
        }
        
        if placeHolderImage != nil {
            self.image = placeHolderImage
        }
        
        self.af_requestImageOperation = (NSBlockOperation(block: { () -> Void in
            var response:NSURLResponse?
            var error:NSError?
            let data = NSURLConnection.sendSynchronousRequest(request, returningResponse: &response, error: &error)
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if request.URL!.isEqual(self.af_requestImageOperation.request?.URL) {
                    var image:UIImage? = (data != nil ? UIImage(data: data!) : nil)
                    if image != nil {
                        if success != nil {
                            success!(request: request, response: response, image: image!)
                        }
                        else {
                            self.image = image!
                        }
                    }
                    else {
                        if failure != nil {
                            println("UIImageView+AFNetworking. setImageWithUrlRequest. Something went wrong")
                            failure!(request: request, response:response, error: error)
                        }
                    }
                    
                    self.af_requestImageOperation = (nil, nil)
                }
            })
        }), request)
        
        UIImageView.af_sharedImageRequestOperationQueue().addOperation(self.af_requestImageOperation.operation!)
    }
    
    private func cancelImageRequestOperation() {
        self.af_requestImageOperation.operation?.cancel()
        self.af_requestImageOperation = (nil, nil)
    }
}

func AFImageCacheKeyFromURLRequest(request:NSURLRequest) -> String {
    return request.URL!.absoluteString!
}

class AFImageCache: NSCache, AFImageCacheProtocol {
    func cachedImageForRequest(request: NSURLRequest) -> UIImage? {
        switch request.cachePolicy {
        case NSURLRequestCachePolicy.ReloadIgnoringLocalCacheData,
        NSURLRequestCachePolicy.ReloadIgnoringLocalAndRemoteCacheData:
            return nil
        default:
            break
        }
        
        return self.objectForKey(AFImageCacheKeyFromURLRequest(request)) as? UIImage
    }
    
    func cacheImage(image: UIImage, forRequest request: NSURLRequest) {
        self.setObject(image, forKey: AFImageCacheKeyFromURLRequest(request))
    }
}




