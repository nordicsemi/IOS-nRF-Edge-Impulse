//
//  DataSamplesFooterView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 30/8/21.
//

import SwiftUI

// MARK: - DataSamplesFooterView

struct DataSamplesFooterView: View {
    
    // MARK: Environment
    
    @EnvironmentObject var appData: AppData
    
    // MARK: Properties
    
    let selectedCategory: DataSample.Category
    
    // MARK: view
    
    var body: some View {
        HStack {
            Text("\(appData.samplesForCategory[selectedCategory]?.count ?? 0) \(selectedCategory.rawValue.uppercasingFirst) Samples")
                .frame(maxWidth: .infinity, alignment: .center)
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }
}
