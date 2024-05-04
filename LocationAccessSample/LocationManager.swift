//
//  LocationManager.swift
//  Ucell
//
//  Created by Vladimir Kazantsev on 30.11.2023.
//

import CoreLocation
import SwiftUI

public enum LocationManagerError: Error {

	/// Доступ к геопозиции был запрещён.
	case authorizationDenied
}

@MainActor
public final class LocationManager: NSObject, ObservableObject {

	public static let shared = LocationManager()

	/// Текущая позиция или `nil`, если позиция недоступна.
	@Published public private(set) var currentPosition: CLLocation?

	private let manager = CLLocationManager()
	private var authorizationRequestContinuation: CheckedContinuation<Void, Error>?
	private var getCurrentPositionContinuation: CheckedContinuation<CLLocation, Error>?

	private override init() {
		super.init()
		
		manager.delegate = self
	}
}

public extension LocationManager {

	func startUpdating() {
		manager.startUpdatingLocation()
	}

	func stopUpdating() {
		manager.stopUpdatingLocation()
		currentPosition = nil
		getCurrentPositionContinuation?.resume(
			throwing: LocationManagerError.authorizationDenied
		)
		getCurrentPositionContinuation = nil
	}


	/// Проверяет наличие доступа к геопозиции.
	/// Если доступ ещё не был запрошен, запрашивает его.
	/// Если доступ к геопозиции есть, возвращает управление нормально.
	/// Если доступ к геопозиции был запрещён, кидает ошибку `LocationManagerError.authorizationDenied`.
	func requestAccess() async throws {

		switch manager.authorizationStatus {
		case .notDetermined:

			try await withCheckedThrowingContinuation { continuation in
				authorizationRequestContinuation = continuation
				manager.requestWhenInUseAuthorization()
			}
		case .restricted, .denied:
			throw LocationManagerError.authorizationDenied

		case .authorized, .authorizedWhenInUse, .authorizedAlways:
			return

		@unknown default:
			return
		}
	}

	func getCurrentPosition() async throws -> CLLocation {

		if let currentPosition {
			return currentPosition
		}

		try await requestAccess()

		return try await withCheckedThrowingContinuation { continuation in

			getCurrentPositionContinuation = continuation
			manager.startUpdatingLocation()
		}
	}
}

/// Делегат для получения позиций и работы с доступами к локации.
extension LocationManager: CLLocationManagerDelegate {

	public func locationManager(
		_ manager: CLLocationManager,
		didChangeAuthorization status: CLAuthorizationStatus
	) {
		switch status {
		case .authorized, .authorizedWhenInUse, .authorizedAlways:
			/// Разрешение получено, возвращаем успех.
			authorizationRequestContinuation?.resume( returning: () )
		case .denied, .restricted, .notDetermined:
			/// Пользователь (или девайс) запретил получение локации.
			authorizationRequestContinuation?.resume(
				throwing: LocationManagerError.authorizationDenied
			)
			currentPosition = nil

		@unknown default:
			authorizationRequestContinuation?.resume( returning: () )
		}

		authorizationRequestContinuation = nil
	}

	public func locationManager(
		_ manager: CLLocationManager,
		didUpdateLocations locations: [ CLLocation ]
	) {
		guard let location = locations.last else {
			return
		}

		currentPosition = location
		getCurrentPositionContinuation?.resume( returning: location )
		getCurrentPositionContinuation = nil
	}
}
