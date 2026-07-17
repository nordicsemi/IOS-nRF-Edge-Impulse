//
//  DataSamplesView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 3/5/21.
//

import SwiftUI
import Combine

struct DataSamplesView: View {
    
    @EnvironmentObject var appData: AppData
    
    // MARK: Properties
    
    @State private var showDataAcquisitionView = false
    
    #if os(OSX)
    private static let toolbarItemPlacement: ToolbarItemPlacement = .secondaryAction
    #else
    private static let toolbarItemPlacement: ToolbarItemPlacement = .primaryAction
    #endif
    
    // MARK: view
    
    static let Columns = [
        GridItem(.fixed(40)),
        GridItem(.flexible()),
        GridItem(.fixed(90)),
        GridItem(.fixed(55))
    ]
    
    var body: some View {
        VStack {
            Picker("Category", selection: $appData.selectedCategory) {
                ForEach(DataSample.Category.allCases) { dataType in
                    Text(dataType.rawValue.uppercasingFirst)
                        .tag(dataType)
                }
            }
            .setAsSegmentedControlStyle()
            #if os(macOS)
            .padding([.horizontal, .bottom])
            #else
            .padding(.horizontal)
            #endif
            
            List {
                Section("Data Samples") {
                    DataSampleHeaderRow()
                    
                    ForEach(appData.samplesForCategory[appData.selectedCategory] ?? []) { sample in
                        DataSampleRow(sample)
                    }
                    
                    DataSamplesFooterView(selectedCategory: appData.selectedCategory)
                }
            }
            #if os(iOS)
            .refreshable { appData.requestDataSamples() }
            #endif
            addHiddenDataAcquisitionNavigationLink()
        }
        .padding(.top)
        .background(Color.formBackground)
        .toolbar {
            ToolbarItem(placement: Self.toolbarItemPlacement) {
                dataAcquisitionToolbarItem()
            }
        }
    }
}

// MARK: - DataSampleHeaderRow

struct DataSampleHeaderRow: View {
    
    var body: some View {
        MultiColumnView(columns: DataSamplesView.Columns) {
            Text("")
            Text("Filename")
                .bold()
            Text("Label")
                .foregroundColor(.nordicMiddleGrey)
            Text("Length")
                .fontWeight(.light)
        }
        .lineLimit(1)
    }
}

// MARK: - Data Acquisition Navigation

private extension DataSamplesView {
    
    func addHiddenDataAcquisitionNavigationLink() -> some View {
        NavigationLink(destination:
                        DataAcquisitionView().environmentObject(appData.dataAquisitionViewState),
                       isActive: $showDataAcquisitionView) {
            EmptyView()
        }
        .hidden()
    }
    
    func dataAcquisitionToolbarItem() -> some View {
        Button(action: {
            showDataAcquisitionView = true
        }) {
            Label("New Sample", systemImage: "plus")
        }
    }
}

// MARK: - Preview

#if DEBUG
import iOS_Common_Libraries

struct DataSamplesView_Previews: PreviewProvider {
    static var previews: some View {
        DataSamplesView()
            .environmentObject(Preview.projectsPreviewAppData)
    }
}
#endif
