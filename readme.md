
Начнём с простого, нам нужно знать текущую позицию и получать информацию о её изменениях. Самое простое и обычно достаточное - это простая `@Published` переменная. Так же сразу добавим `CLLocationManager` для собственно определения позиции.

```swift
@MainActor
public final class LocationManager: NSObject, ObservableObject {

	/// Текущая позиция или `nil`, если позиция недоступна.
	@Published public private(set) var currentPosition: CLLocation?

	/// Это синглтон, так как зачем нужно что-то ещё?
	public static let shared = LocationManager()
    
    /// Собственно определятель текущей позиции.
   	private let manager = CLLocationManager()

	private override init() {
		super.init()
        manager.delegate = self
    }
}

/// Делегат для получения позиций и работы с доступами к локации.
extension LocationManager: CLLocationManagerDelegate {

	public func locationManager(
		_ manager: CLLocationManager,
		didUpdateLocations locations: [ CLLocation ]
	) {
		guard let location = locations.last else {
			return
		}

		currentPosition = location
	}
}
```

Если Нам нужна работа с UIKit, тогда вместо (или вместе) `@Published` можно использовать `CurrentValueSubject<CLLocation?, Never>` из Комбайна. Или, если совсем уходить в `async/await`, то перейти на `AsyncStream<CLLocation?>`.

Далее, добавляем методы для начала и завершения мониторинга локации:
```
public extension LocationManager {

	func startUpdating() {
		manager.startUpdatingLocation()
	}

	func stopUpdating() {
		manager.stopUpdatingLocation()
		currentPosition = nil
	}
```

Теперь нужно добавить запрос разрешения на получение локации. В `CLlocationManager` это делается через делегат, поэтому достаточно просто обернуть это в `async` метод. Для этого нам нужна переменная с "продолжением" ...
```
public final class LocationManager: NSObject, ObservableObject {

	....
    
   	private var authorizationRequestContinuation: CheckedContinuation<Void, Error>?
}
```

... метод делегата, который будет передавать результат в это "продолжение":

```
extension LocationManager: CLLocationManagerDelegate {

	...

	public func locationManager(
		_ manager: CLLocationManager,
		didChangeAuthorization status: CLAuthorizationStatus
	) {
		switch status {
        /// Разрешение получено, возвращаем успех.
		case .authorized, .authorizedWhenInUse, .authorizedAlways:
			authorizationRequestContinuation?.resume( returning: () )
        /// Пользователь (или девайс) запретил получение локации.
		case .denied, .restricted, .notDetermined:
			authorizationRequestContinuation?.resume(
				throwing: LocationManagerError.authorizationDenied
			)
			currentPosition = nil

		@unknown default:
			authorizationRequestContinuation?.resume( returning: () )
		}

		authorizationRequestContinuation = nil
	}
}
```

... для удобства добавим ошибку, которую будем кидать, если доступ запрещён.

```
public enum LocationManagerError: Error {

	/// Доступ к геопозиции был запрещён.
	case authorizationDenied
}
```

... и собственно метод с запросом:

```
public extension LocationManager {

	....
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
}
```

По вопросу одновременного запроса доступа из нескольких мест - поскольку запрос происходит системным окном, которое блокирует приложение от пользователя, очень маловероятно, что нужно предусматривать такой вариант. Если такая необходимость есть, нужно будет поиграть с `Task`, в который обёртывать вышеуказанный `func requestAccess`.

Далее, нам нужен запрос текущей позиции для случаев, когда пользователь, например, жмёт на карте кнопку "Показать текущее местоположение". Тут уже всё совсем просто - запрашиваем доступ и возвращаем ждём позицию, если её ещё нет:

```
public final class LocationManager: NSObject, ObservableObject {

	....
    
	private var getCurrentPositionContinuation: CheckedContinuation<CLLocation, Error>?
}

public extension LocationManager {

	....

	/// Возвращает текущую позицию или кидает ошибку, если доступ к позиции
    /// запрещён пользователем.
	func getCurrentPosition() async throws -> CLLocation {

		// Если у нас уже есть текущая локация, просто возвращаем её.
		if let currentPosition {
			return currentPosition
		}

		// Если позиции нет, проверяем/запрашиваем доступ к ней.
		try await requestAccess()

		// После получения доступа к позиции ждём её первого определения.
		return try await withCheckedThrowingContinuation { continuation in

			getCurrentPositionContinuation = continuation
            // Запускаем обновление, так как это логично.
			manager.startUpdatingLocation()
		}
	}
}
```

Осталось только добавить отправку геопозиции в `getCurrentPositionContinuation` при появлении её в методе делегата. Для этого добавим две строчки:

```
....
	public func locationManager(
		_ manager: CLLocationManager,
		didUpdateLocations locations: [ CLLocation ]
	) {
		guard let location = locations.last else {
			return
		}

		currentPosition = location
        
        // Если приложение ждёт появления позиции, отдаём её тут.
		getCurrentPositionContinuation?.resume( returning: location )
		getCurrentPositionContinuation = nil
	}
...
```

Опять же скорее всего двух одновременных запросов `getCurrentPosition` логически быть не должно, но если это нужно предусмотреть, то превращаем `getCurrentPositionContinuation` и при получении позиции отправляем её во все "продолжения" из этого массива.


