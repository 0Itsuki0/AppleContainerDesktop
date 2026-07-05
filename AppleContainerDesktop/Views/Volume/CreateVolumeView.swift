//
//  CreateVolumeView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/11/03.
//


import SwiftUI

internal import ContainerizationOCI


struct CreateVolumeView: View {
    
    @Environment(ApplicationManager.self) private var applicationManager
    @Environment(\.dismiss) private var dismiss
            
    @SwiftUI.State private var name: String = ""
    @SwiftUI.State private var options: [KeyValueModel] = []
    @SwiftUI.State private var labels: [KeyValueModel] = []
    @SwiftUI.State private var size: UInt64 = 1
    @SwiftUI.State private var sizeType: SizeType = .MB
    

    @SwiftUI.State private var showAdditionalSettings: Bool = false

    @SwiftUI.State private var errorMessage: String?
    
    // use a different one then applicationManager.showProgressView to show the progress view over this sheet
    @SwiftUI.State private var showProgressView: Bool = false


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Create New Volume")
                        .font(.headline)
                                        
                    if let errorMessage = self.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)

                    }
                }

                
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Volume Name")

                    TextField(text: $name, prompt: Text("Ex: volume-1"), label: {})
                }


                
                Divider()
                
                
                Button(action: {
                    showAdditionalSettings.toggle()
                }, label: {
                    HStack {
                        Text("Optional Settings")
                        Spacer()
                        Image(systemName: showAdditionalSettings ? "chevron.up" : "chevron.down")
                            .padding(.trailing, 4)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
                
                if showAdditionalSettings {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Volume Size")

                        HStack {
                            TextField("", value: $size, format: .number)

                            Picker(selection: $sizeType, content: {
                                ForEach(SizeType.allCases, content: { sizeType in
                                    Text(sizeType.rawValue)
                                        .tag(sizeType)
                                })
                            }, label: { })

                        }
                    }
                    
                    KeyValuesEditView(keyValues: $labels, title: "Volume Metadata (Label)")
                    KeyValuesEditView(keyValues: $options, title: "Driver Specific Options")

                }
                
                
                Divider()
                
                HStack(spacing: 16) {
                    Button(action: {
                        self.dismiss()
                    }, label: {
                        Text("Cancel")
                            .padding(.horizontal, 2)
                    })
                    .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .secondary))
                    
                    Button(action: {
                        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else {
                            self.errorMessage = "Name is not specified."
                            return
                        }

                        Task {
                            self.showProgressView = true
                            
                            do {
                                let validLabels = self.labels.filter({!$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty})
                                let validOptions = self.options.filter({!$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty})

                                try await VolumeService.createVolume(name: name, labels: validLabels, options: validOptions, size: (self.size, self.sizeType), messageStreamContinuation: self.applicationManager.messageStreamContinuation)

                                self.dismiss()
                                
                            } catch (let error) {
                                self.errorMessage = "\(error)"
                            }
                            
                            self.showProgressView = false
                        }
                    }, label: {
                        Text("Create")
                            .padding(.horizontal, 2)
                    })
                    .buttonStyle(CustomButtonStyle(backgroundShape: .roundedRectangle(4), backgroundColor: .blue))
                }
                
                .frame(maxWidth: .infinity, alignment: .trailing)
                    
            }
            .multilineTextAlignment(.leading)
            .padding(.all, 24)
            .scrollTargetLayout()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: !self.showAdditionalSettings)
        .frame(maxHeight: 440)
        .sheet(isPresented: $showProgressView, content: {
            CustomProgressView()
                .environment(self.applicationManager)
        })
        .animation(.default, value: self.labels.count)
        .animation(.default, value: self.options.count)
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()

    }
}
