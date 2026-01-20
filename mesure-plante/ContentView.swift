//
//  ContentView.swift
//  mesure-plante
//
//  Created by macbook on 19/01/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var scannedQRData: QRCodeData?

    var body: some View {
        Group {
            if let qrData = scannedQRData {
                // Vue AR après scan réussi
                ARMeasureView(qrData: qrData)
            } else {
                // Scanner QR Code au démarrage
                QRScannerView(scannedData: $scannedQRData)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
