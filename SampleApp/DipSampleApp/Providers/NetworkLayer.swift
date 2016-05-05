//
//  NetworkLayer.swift
//  Dip
//
//  Created by Olivier Halligon on 10/10/2015.
//  Copyright © 2015 AliSoftware. All rights reserved.
//

import Foundation

enum NetworkResponse {
    case Success(NSData, NSHTTPURLResponse)
    case Error(NSError)
    
    func unwrap() throws -> (NSData, NSHTTPURLResponse) {
        switch self {
        case Success(let data, let response):
            return (data, response)
        case Error(let error):
            throw error
        }
    }
    
    func json<T>() throws -> T {
        let (data, _) = try self.unwrap()
        let obj = try NSJSONSerialization.jsonObject(with: data, options: [])
        guard let json = obj as? T else {
            throw SWAPIError.InvalidJSON
        }
        return json
    }
}

protocol NetworkLayer {
    func request(path: String, completion: NetworkResponse -> Void)
}
