//
//  AddAPIKeyRequest.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 14/07/2026.
//

import Foundation
import iOS_Common_Libraries

// MARK: - Request

extension HTTPRequest {
    
    static func addAPIKey(for project: Project, using apiToken: String) -> HTTPRequest? {
        let bundle = Bundle(for: AppData.self)
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                       ?? "nRF Edge Impulse"
        let body = AddAPIKeyBody(name: appName.appending(" for iOS"), isDevelopmentKey: true, role: .admin)
        
        guard var httpRequest = HTTPRequest(host: .EdgeImpulse, path: "/v1/api/\(project.id)/apikeys"),
              let bodyData = try? JSONEncoder().encode(body) else { return nil }
        let jwtValue = "jwt=" + apiToken
        httpRequest.setMethod(.POST)
        httpRequest.setHeaders(["cookie": jwtValue, "Accept": "application/json", "Content-Type": "application/json"])
        httpRequest.setBody(bodyData)
        return httpRequest
    }
}

// MARK: - AddAPIKeyBody

fileprivate struct AddAPIKeyBody: Codable {
    
    enum Role: String, RawRepresentable, CaseIterable, Codable {
        case admin = "admin"
        case readOnly = "readonly"
        case ingestionOnly = "ingestiononly"
        case ingestionDeployment = "ingestion_deployment"
    }
    
    let name: String
    let isDevelopmentKey: Bool
    let role: Role
}

// MARK: - Response

struct AddAPIKeyResponse: HTTPResponse {
    
    let success: Bool
    let error: String?
    
    let id: Int
    let apiKey: String
}
