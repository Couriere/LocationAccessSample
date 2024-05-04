//
//  ContentView.swift
//  LocationAccessSample
//
//  Created by Vladimir Kazantsev on 04.05.2024.
//

import CoreLocation
import SwiftUI

public struct ContentView {
	
	@ObservedObject private var locationManager = LocationManager.shared
	
	@State private var requestedPosition: String = "Position was not requested yet"
	@State private var requestInProgress: Bool = false
}

extension ContentView: View {

	public var body: some View {
        
		VStack( spacing: 32 ) {

			Text( "Current postition: \( locationManager.currentPosition?.position ?? "No position" )" )


			VStack( spacing: 8 ) {
				Button( action: requestCurrentPosition ) {
					ZStack {
						Text( "Request position" )
							.opacity( requestInProgress ? 0 : 1 )

						if requestInProgress {
							ProgressView()
						}
					}
				}
				.disabled( requestInProgress )

				Text( requestedPosition )
					.font( .caption )
			}
        }
		.buttonStyle( .bordered )
		.frame(maxHeight: .infinity, alignment: .top)
        .padding()
    }
}

private extension ContentView {

	func requestCurrentPosition() {

		requestInProgress = true

		Task {
			defer { requestInProgress = false }

			do {
				let location = try await locationManager.getCurrentPosition()
				requestedPosition = location.position
			}
			catch {
				requestedPosition = "Location request denied"
			}
		}
	}
}

extension CLLocation {

	var position: String {

		let latitude = coordinate.latitude
			.formatted( .number.precision( .fractionLength( 2 )))
		let longitude = coordinate.longitude
			.formatted( .number.precision( .fractionLength( 2 )))
		return "\( latitude ); \( longitude )"
	}
}

#Preview {
    ContentView()
}
