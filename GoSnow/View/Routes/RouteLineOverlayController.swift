//
//  RouteLineOverlayController.swift
//  GoSnow
//
//  Created by OpenAI on 2025/02/14.
//
import Foundation
import MapboxMaps
import CoreLocation

@MainActor
final class RouteLineOverlayController: ObservableObject {
    private weak var mapView: MapView?
    private let sourceId = "route-line-source"
    private let casingLayerId = "route-line-casing"
    private let lineLayerId = "route-line"
    private var didInstall = false
    private var styleLoadedCancellable: Cancelable?
    private var pendingCoords: [CLLocationCoordinate2D] = []

    private(set) var isEmpty: Bool = true

    func attach(to mapView: MapView) {
        self.mapView = mapView
        installWhenStyleReady()
    }

    func render(_ coords: [CLLocationCoordinate2D]) {
        pendingCoords = coords
        isEmpty = coords.isEmpty
        guard let mapView, mapView.mapboxMap.isStyleLoaded else { return }
        if !didInstall {
            install()
        }
        apply(coords)
    }

    func clear() {
        pendingCoords = []
        isEmpty = true
        guard let mapView, mapView.mapboxMap.isStyleLoaded else { return }
        let empty = FeatureCollection(features: [])
        mapView.mapboxMap.updateGeoJSONSource(withId: sourceId, geoJSON: .featureCollection(empty))
    }

    func cameraOptions(for coords: [CLLocationCoordinate2D]) -> CameraOptions {
        guard coords.count >= 2 else {
            return CameraOptions(center: coords.first, zoom: 14)
        }
        var minLat =  90.0, maxLat = -90.0
        var minLon =  180.0, maxLon = -180.0
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let sw = CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
        let ne = CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        let bounds = CoordinateBounds(southwest: sw, northeast: ne)
        let padding = UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40)
        return mapView?.mapboxMap.camera(for: bounds, padding: padding, bearing: 0, pitch: 0) ?? CameraOptions(center: coords.first, zoom: 14)
    }

    private func apply(_ coords: [CLLocationCoordinate2D]) {
        guard let mapView else { return }
        guard coords.count >= 2 else {
            let empty = FeatureCollection(features: [])
            mapView.mapboxMap.updateGeoJSONSource(withId: sourceId, geoJSON: .featureCollection(empty))
            return
        }
        let line = LineString(coords)
        let feature = Feature(geometry: .lineString(line))
        let collection = FeatureCollection(features: [feature])
        mapView.mapboxMap.updateGeoJSONSource(withId: sourceId, geoJSON: .featureCollection(collection))
    }

    private func installWhenStyleReady() {
        guard let mapView else { return }
        if mapView.mapboxMap.isStyleLoaded {
            install()
        } else {
            styleLoadedCancellable?.cancel()
            styleLoadedCancellable = mapView.mapboxMap.onStyleLoaded.observeNext { [weak self] _ in
                Task { @MainActor in self?.install() }
            }
        }
    }

    private func install() {
        guard let mapView, mapView.mapboxMap.isStyleLoaded else { return }
        guard !didInstall else { return }
        didInstall = true

        try? mapView.mapboxMap.removeLayer(withId: lineLayerId)
        try? mapView.mapboxMap.removeLayer(withId: casingLayerId)
        try? mapView.mapboxMap.removeSource(withId: sourceId)

        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        try? mapView.mapboxMap.addSource(source)

        var casing = LineLayer(id: casingLayerId, source: sourceId)
        casing.lineColor = .constant(StyleColor(.black))
        casing.lineOpacity = .constant(0.5)
        casing.lineWidth = .constant(6)
        casing.lineJoin = .constant(.round)
        casing.lineCap = .constant(.round)
        try? mapView.mapboxMap.addLayer(casing)

        var line = LineLayer(id: lineLayerId, source: sourceId)
        line.lineColor = .constant(StyleColor(.systemBlue))
        line.lineOpacity = .constant(0.95)
        line.lineWidth = .constant(3.5)
        line.lineJoin = .constant(.round)
        line.lineCap = .constant(.round)
        try? mapView.mapboxMap.addLayer(line)

        if !pendingCoords.isEmpty {
            apply(pendingCoords)
        }
    }
}
