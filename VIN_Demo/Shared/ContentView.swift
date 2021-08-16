//
//  ContentView.swift
//  Shared
//
//  Created by Paul Nelson on 8/15/21.
//

import SwiftUI
import VehicleIdentificationNumber

struct ContentView: View {
    @ObservedObject var vin = VehicleIdentificationNumber()
    @State private var alertShowing = false
    @State private var alertTitle = ""
    @State private var alertError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter a VIN:")
            HStack {
                TextField("Enter a VIN", text: $vin.VIN)
                Spacer()
                if vin.isValid {
                    Button(action: fetchInfo) {
                        Label("", systemImage: "info.circle")
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(vin.VIN.count == 17 ? .red : .yellow)
                }
            }
            List {
                ForEach( vin.details ) { detail in
                    VStack(alignment: .leading) {
                        Text(detail.name).font(.caption)
                        Text(detail.value)
                    }
                }
            }
        }
        .padding(20)
        .alert(isPresented: $alertShowing, content: {
            Alert(title: Text(alertTitle),
                  message: Text(alertError), dismissButton: .default(Text("OK")))
        })
    }
    private func fetchInfo() {
        vin.fetch { encoded, error in
            if let err = error {
                alertTitle = "Vehicle Lookup Failed"
                alertError = err.localizedDescription
                alertShowing = true
            } else if let errorText = vin.information["ErrorText"] {
                if errorText.hasPrefix("0") == false {
                    alertTitle = "Vehicle Lookup Error"
                    alertError = errorText
                    alertShowing = true
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
