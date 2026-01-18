//
//  RecordingView.swift
//  GoSnow
//
//  Created by federico Liu on 2024/8/4.
//

import SwiftUI
import MapboxMaps
import CoreLocation
import Snap
import UIKit

struct RecordingView: View {

    @State private var mapView: MapView?
    private let mapStyle: RecordingMapStyle = .contour

    @State private var isEnding = false
    @State private var showMap = true
    @State private var summaryToPresent: SessionSummary? = nil

    private let authLM = CLLocationManager()
    @State private var didSetInitialCamera = false

    // ✅ toast
    @State private var trackToast: String = ""
    @State private var showTrackToast: Bool = false
    @State private var toastTask: Task<Void, Never>? = nil

    // ✅ 用一个数来表达 “抽屉现在大概会遮住多少高度”
    @State private var drawerExtraBottom: CGFloat = 240

    @State private var toastSeq: Int = 0

    @State private var routeImageToPresent: UIImage? = nil
    @State private var lastSessionIdForSummary: UUID? = nil

    // ✅ 3D 开关
    @State private var is3D: Bool = false

    // ✅ 共享 VM：地图和底部控制用同一份
    @StateObject private var vm = RecordingViewModel(
        recorder: BasicSessionRecorder(
            location: CoreLocationService(),
            metrics: BasicMetricsComputer()
        ),
        store: JSONLocalStore()
    )
    
    // ✅ 轨迹控制器
    @StateObject private var track = LiveTrackController()
    @State private var trackEnabled: Bool = true

    // ✅ 跟随路线 overlay
    @StateObject private var activeRouteOverlay = RouteLineOverlayController()
    @AppStorage("activeRouteId") private var activeRouteId: String = ""
    
    // ✅ 小队 controller
    @StateObject private var party = PartyRideController()
    
    //
    @State private var showPartySheet = false

    //
    @State private var routeRenderFailed: Bool = false
    @State private var routeRenderErrorText: String = ""

    //
    @State private var isGeneratingRouteForSummary: Bool = false

    

    var body: some View {
        ZStack {
            if showMap {
                MapBlock
                    .safeAreaInset(edge: .top) {
                        partyTopInsetBar
                    }
                    .overlay(alignment: .bottomTrailing) {
                        trackOverlay
                    }

            }


            ControlBlock
                .allowsHitTesting(!isEnding)
                .opacity(isEnding ? 0.4 : 1)

            if isEnding {
                Color.black.opacity(0.001).ignoresSafeArea()
                ProgressView("保存中…")
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            didSetInitialCamera = false
            ensureMapAuthorization()
            track.isEnabled = trackEnabled
        }
        .task(id: activeRouteId) {
            await loadActiveRouteOverlay()
        }
        // ✅ 有新坐标就追加到轨迹
        .onChange(of: vm.currentCoordinate) { _, c in
            guard let c else { return }
            track.append(c, speedKmh: vm.speedKmh)
            // ✅ 小队：只要加入了就会发（内部已做 1s 广播 / 30s 写库）
            party.onMyLocation(c)
        }
        // ✅ 开关变化
        .onChange(of: trackEnabled) { _, on in
            track.isEnabled = on
        }
        // ✅ 每次从 idle -> recording，重置轨迹
        .onChange(of: vm.state) { old, new in
            if old == .idle && new == .recording {
                track.reset()
            }
        }
        .fullScreenCover(item: $summaryToPresent) { s in
            SessionSummaryScreen(
                summary: s,
                routeImage: routeImageToPresent,
                isGeneratingRoute: isGeneratingRouteForSummary
            ) {
                summaryToPresent = nil
                routeImageToPresent = nil
                lastSessionIdForSummary = nil
                isGeneratingRouteForSummary = false

                isEnding = false
                showMap = true
                mapView?.isUserInteractionEnabled = true
            }
        }

    }

    // MARK: - Map

    private var MapBlock: some View {
            MapViewRepresentable(style: mapStyle) { map in
            DispatchQueue.main.async {
                self.mapView = map
                configureInitialCameraIfNeeded()
                track.attach(to: map) // ✅ 内部会等 styleLoaded 再装 layer
                party.attach(to: map)
                activeRouteOverlay.attach(to: map)
            }
        }
        .ignoresSafeArea()
    }
    
    private var partyTopInsetBar: some View {
        HStack {
            Spacer(minLength: 0)
            PartyHUDView(party: party)
            Spacer(minLength: 0)
        }
        .padding(.top, 50)          // 这几个值你按“跟返回键同一行”的视觉微调
        .padding(.bottom, 6)
        .padding(.horizontal, 14)
        .background(Color.clear)
    }



    private func configureInitialCameraIfNeeded() {
        guard !didSetInitialCamera, let map = mapView else { return }
        didSetInitialCamera = true

        let coord = authLM.location?.coordinate
        let camera: CameraOptions

        if let c = coord {
            camera = CameraOptions(center: c, zoom: 17, bearing: 0, pitch: 0)
        } else {
            camera = CameraOptions(center: nil, zoom: 2)
        }
        map.mapboxMap.setCamera(to: camera)
    }

    // MARK: - Floating Buttons (3D + Track) + Toast

    private var trackOverlay: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {

                // Toast（按钮上方，避免挡住双按钮）
                if showTrackToast {
                    Text(trackToast)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .padding(.trailing, 64)
                        .padding(.bottom, trackBottomPadding(in: geo) + overlayButtonsTotalHeight + 10)
                }

                // ✅ 双按钮：上 3D / 下 轨迹
                VStack(spacing: 10) {
                    
                    
                    // ✅ 组队按钮（永远不变，只负责打开 sheet）
                        Button {
                            showPartySheet = true
                        } label: {
                            Image(systemName: "person.wave.2") // 你也可以换 person.2.badge.plus
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.blue)
                                .frame(width: 44, height: 44)
                                .background(.thinMaterial)
                                .clipShape(Circle())
                        }
                        .shadow(radius: 6)

                    // 3D 按钮
                    Button {
                        is3D.toggle()
                        set3D(is3D)
                        show3DToast()
                    } label: {
                        Image(systemName: is3D ? "cube.fill" : "cube")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(is3D ? Color.blue : Color.blue) // 只给图标上色
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                    }
                    .shadow(radius: 6)

                    // 轨迹按钮（你原来的）
                    Button {
                        trackEnabled.toggle()
                        track.isEnabled = trackEnabled

                        if trackEnabled {
                            track.reset()
                        }

                        showTrackStatusToast()
                    } label: {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(trackEnabled ? Color.blue : Color.gray) // 只给图标上色
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                    }
                    .shadow(radius: 6)
                }
                .padding(.trailing, 14)
                .padding(.bottom, trackBottomPadding(in: geo))
                .allowsHitTesting(!isEnding)
                .opacity(isEnding ? 0.4 : 1.0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            
            .sheet(isPresented: $showPartySheet) {
                PartySheetHostView(party: party)
            }

        }
        .ignoresSafeArea()
    }

    private var overlayButtonsTotalHeight: CGFloat {
        44 + 10 + 44
    }

    private func trackBottomPadding(in geo: GeometryProxy) -> CGFloat {
        let base = 24 + geo.safeAreaInsets.bottom
        return base + drawerExtraBottom
    }

    @MainActor
    private func set3D(_ on: Bool) {
        guard let map = mapView else { return }

        let targetPitch: CGFloat = on ? 60 : 0
        let state = map.mapboxMap.cameraState

        let cam = CameraOptions(
            center: state.center,
            zoom: state.zoom,
            bearing: state.bearing,
            pitch: targetPitch
        )

        map.camera.ease(to: cam, duration: 0.8, curve: .easeInOut)
    }

    @MainActor
    private func show3DToast() {
        toastSeq += 1
        let seq = toastSeq

        toastTask?.cancel()
        toastTask = nil

        showTrackToast = false
        trackToast = is3D ? "3D 已开启" : "已切回 2D"

        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.18)) {
                showTrackToast = true
            }
        }

        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard seq == toastSeq else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                showTrackToast = false
            }
        }
    }

    @MainActor
    private func showTrackStatusToast() {
        toastSeq += 1
        let seq = toastSeq

        toastTask?.cancel()
        toastTask = nil

        showTrackToast = false
        trackToast = trackEnabled ? "轨迹已开启" : "轨迹已关闭"

        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.18)) {
                showTrackToast = true
            }
        }

        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard seq == toastSeq else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                showTrackToast = false
            }
        }
    }

    // MARK: - Control

    private var ControlBlock: some View {
        VStack(spacing: 0) {
            Spacer()
            SnapDrawer(
                large: .paddingToTop(500),
                medium: .fraction(0.4),
                tiny: .height(100),
                allowInvisible: false
            ) { state in

                ZStack(alignment: .topTrailing) {
                    Recents(
                        vm: vm,
                        onWillStop: { [weakMap = mapView] in
                            isEnding = true
                            weakMap?.isUserInteractionEnabled = false
                            showMap = false
                            clearActiveRoute()
                        },
                        onSummary: { summary, session in
                            // ✅ 1) 先立刻打开总结页
                            lastSessionIdForSummary = session.id
                            routeImageToPresent = nil
                            summaryToPresent = summary

                            // ✅ 2) 判断是否“有轨迹可生成”
                            let segs = track.snapshotSegments()

                            // 没轨迹：总结页应显示“暂无轨迹”，不要转圈
                            guard !segs.isEmpty else {
                                isGeneratingRouteForSummary = false
                                return
                            }

                            // 有轨迹：总结页显示“生成中”
                            isGeneratingRouteForSummary = true

                            // ✅ 3) 离线生成抽象轨迹图（不依赖网络 / Mapbox）
                            Task.detached(priority: .utility) {
                                do {
                                    let renderSize = CGSize(width: 900, height: 900)

                                    let image = RouteThumbnailRenderer.render(
                                        size: renderSize,
                                        segments: segs.map { .init(coords: $0.coords, bucket: $0.bucket) }
                                    )

                                    try JSONLocalStore().saveRouteImage(image, sessionId: session.id)

                                    await MainActor.run {
                                        if lastSessionIdForSummary == session.id {
                                            routeImageToPresent = image
                                            isGeneratingRouteForSummary = false   // ✅ 成功后关闭“生成中”
                                        }
                                    }
                                } catch {
                                    await MainActor.run {
                                        if lastSessionIdForSummary == session.id {
                                            isGeneratingRouteForSummary = false   // ✅ 失败也别一直转圈
                                        }
                                    }
                                }
                            }
                        }




                    )
                    .opacity(state == .tiny || isEnding ? 0 : 1)
                    .allowsHitTesting(state != .tiny && !isEnding)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }
                .onAppear {
                    switch state {
                    case .tiny:   drawerExtraBottom = 120
                    case .medium: drawerExtraBottom = 240
                    case .large:  drawerExtraBottom = 420
                    }
                }
                .onChange(of: state) { _, newState in
                    switch newState {
                    case .tiny:   drawerExtraBottom = 120
                    case .medium: drawerExtraBottom = 240
                    case .large:  drawerExtraBottom = 420
                    }
                }
            }
        }
    }

    // MARK: - Location auth

    private func ensureMapAuthorization() {
        let status = authLM.authorizationStatus
        switch status {
        case .notDetermined:
            authLM.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    @MainActor
    private func loadActiveRouteOverlay() async {
        guard !activeRouteId.isEmpty else {
            activeRouteOverlay.clear()
            return
        }
        guard let routeUUID = UUID(uuidString: activeRouteId) else {
            activeRouteOverlay.clear()
            return
        }

        if let cached = RouteTrackCache.load(routeId: routeUUID) {
            if let coords = try? RoutesAPI.shared.decodeTrackCoordinates(from: cached) {
                activeRouteOverlay.render(coords)
                return
            }
        }

        do {
            guard let detail = try await RoutesAPI.shared.fetchRouteDetail(routeId: routeUUID) else {
                return
            }
            guard let url = detail.trackFileUrl else {
                return
            }
            let data = try await RoutesAPI.shared.downloadTrackData(trackFileUrl: url)
            RouteTrackCache.save(data, routeId: routeUUID)
            let coords = try RoutesAPI.shared.decodeTrackCoordinates(from: data)
            activeRouteOverlay.render(coords)
        } catch {
            print("❌ loadActiveRouteOverlay failed:", error)
        }
    }

    private func clearActiveRoute() {
        activeRouteId = ""
        activeRouteOverlay.clear()
    }
    
    private func cameraOptionsToFit(coords: [CLLocationCoordinate2D], padding: CGFloat) -> CameraOptions {
        guard coords.count >= 2 else {
            return CameraOptions(center: coords.first, zoom: 16, bearing: 0, pitch: 0)
        }

        var minLat =  90.0, maxLat = -90.0
        var minLon =  180.0, maxLon = -180.0
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        // 用你 RouteSnapshotter 里那套 WebMercator 算 zoom（复制简化版）
        func xNorm(_ lon: Double) -> Double { (lon + 180.0) / 360.0 }
        func yNorm(_ lat: Double) -> Double {
            let rad = lat * .pi / 180.0
            let sinv = sin(rad)
            let y = 0.5 - log((1 + sinv) / (1 - sinv)) / (4 * .pi)
            return min(max(y, 0), 1)
        }

        let x1 = xNorm(minLon), x2 = xNorm(maxLon)
        let y1 = yNorm(minLat), y2 = yNorm(maxLat)
        let dx = abs(x2 - x1)
        let dy = abs(y2 - y1)

        // 这里用“屏幕宽度”做估算（你出图是裁正方形，足够用了）
        let w = Double(UIScreen.main.bounds.width - padding * 2)
        let h = w
        let tileSize = 512.0

        let zoom: Double = {
            if dx < 1e-9 && dy < 1e-9 { return 16.0 }
            let scaleX = w / max(dx, 1e-9)
            let scaleY = h / max(dy, 1e-9)
            let scale = min(scaleX, scaleY)
            let z = log2(scale / tileSize)
            return min(max(z, 0), 22)
        }()

        return CameraOptions(center: center, zoom: zoom, bearing: 0, pitch: 0)
    }

    private func cropCenterSquare(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }

        let w = cg.width
        let h = cg.height
        let side = min(w, h)

        let x = (w - side) / 2
        let y = (h - side) / 2
        let rect = CGRect(x: x, y: y, width: side, height: side)

        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

}










/*
 import SwiftUI
 import MapKit
 import CoreLocation
 import Snap

 struct RecordingView: View {
     @State private var is3DMode = false
     @State private var isSatelliteMode = false
     @State private var mapView: MKMapView?

     @State private var userLocation: CLLocationCoordinate2D?
     @State private var didSetInitialCamera = false

     // 结束流程遮罩
     @State private var isEnding = false
     @State private var showMap = true

     // 总结数据
     @State private var summaryToPresent: SessionSummary? = nil

     // 本地权限请求器（只为蓝点&跟随）
     private let authLM = CLLocationManager()

     // 坐标变更“键”（避免频繁相机抖动）
     private struct CoordKey: Equatable {
         let lat: Int
         let lon: Int
     }
     private var userLocationKey: CoordKey? {
         guard let c = userLocation else { return nil }
         return CoordKey(
             lat: Int(c.latitude  * 1_000_000),
             lon: Int(c.longitude * 1_000_000)
         )
     }

     var body: some View {
         ZStack {
             if showMap { MapBlock }

             // 右侧抽屉（你的 Recents）
             ControlBlock
                 .allowsHitTesting(!isEnding)
                 .opacity(isEnding ? 0.4 : 1)

             // ✅ 右侧“浮动区”——与原代码一致：竖排两个按钮（2D/3D、标准/卫星）
             RightSideControls
                 .allowsHitTesting(!isEnding)
                 .opacity(isEnding ? 0.4 : 1)

             // 结束遮罩
             if isEnding {
                 Color.black.opacity(0.001).ignoresSafeArea()
                 ProgressView("保存中…")
                     .padding()
                     .background(.thinMaterial)
                     .clipShape(RoundedRectangle(cornerRadius: 12))
             }
         }
         .onAppear {
             didSetInitialCamera = false
             ensureMapAuthorization()   // 进入时申请定位权限（让蓝点能出现）
         }
         .fullScreenCover(item: $summaryToPresent) { s in
             SessionSummaryScreen(summary: s) {
                 // 关闭总结：关 cover + 恢复地图交互 & 跟随
                 summaryToPresent = nil
                 isEnding = false
                 showMap = true
                 if let map = mapView {
                     map.isUserInteractionEnabled = true
                     map.setUserTrackingMode(.follow, animated: false)
                 }
             }
         }
     }

     // MARK: - 地图块
     private var MapBlock: some View {
         MapViewRepresentable(userLocation: $userLocation) { map in
             DispatchQueue.main.async {
                 self.mapView = map

                 // 初始配置（保持与原思路一致）
                 map.mapType = isSatelliteMode ? .satellite : .standard
                 map.pointOfInterestFilter = .includingAll
                 map.showsUserLocation = true
                 map.setUserTrackingMode(.follow, animated: false)

                 map.isZoomEnabled = true
                 map.isScrollEnabled = true
                 map.isRotateEnabled = true
                 map.isPitchEnabled = true
                 map.showsCompass = true

                 // 没有坐标时，尽量给个近似镜头
                 if self.userLocation == nil {
                     if let approx = authLM.location?.coordinate {
                         let camera = MKMapCamera(lookingAtCenter: approx,
                                                  fromDistance: is3DMode ? 1000 : 3000,
                                                  pitch: is3DMode ? 45 : 0,
                                                  heading: 0)
                         map.setCamera(camera, animated: false)
                     }
                 }
             }
         }
         .ignoresSafeArea()
         // 首次把相机拉到正确位置；之后交给 .follow
         .onChange(of: userLocationKey) { _, _ in
             guard let coord = userLocation, let map = self.mapView else { return }
             if !didSetInitialCamera {
                 didSetInitialCamera = true
                 let cam = MKMapCamera(lookingAtCenter: coord,
                                       fromDistance: is3DMode ? 1000 : 3000,
                                       pitch: is3DMode ? 45 : 0, heading: 0)
                 map.setCamera(cam, animated: true)
                 map.setUserTrackingMode(.follow, animated: false)
             }
         }
     }

     // MARK: - 控制抽屉（含 Recents）
     // 保留你的抽屉与结束流程逻辑，不再在抽屉里放地图按钮条
     private var ControlBlock: some View {
         VStack(spacing: 0) {
             Spacer()
             SnapDrawer(
                 large: .paddingToTop(500),
                 medium: .fraction(0.4),
                 tiny: .height(100),
                 allowInvisible: false
             ) { state in
                 ZStack(alignment: .topTrailing) {
                     Recents(
                         onWillStop: { [weakMap = mapView] in
                             // 结束：先撤下重组件 & 禁止交互
                             isEnding = true
                             weakMap?.setUserTrackingMode(.none, animated: false)
                             weakMap?.isUserInteractionEnabled = false
                             weakMap?.delegate = nil
                             showMap = false
                         },
                         onSummary: { s in
                             // 完全错开后再展示总结页
                             summaryToPresent = s
                         }
                     )
                     .opacity(state == .tiny || isEnding ? 0 : 1)
                     .allowsHitTesting(state != .tiny && !isEnding)
                     .padding(.horizontal, 16)
                     .padding(.top, 24)
                     .padding(.bottom, 12)
                 }
             }
         }
     }

     // MARK: - 右侧浮动区（2D/3D、标准/卫星）
     private var RightSideControls: some View {
         VStack {
             Spacer()
             VStack(spacing: 16) {
                 // 2D / 3D
                 Button {
                     is3DMode.toggle()
                     updateMapViewMode()
                 } label: {
                     Image(systemName: is3DMode ? "view.3d" : "view.2d")
                         .resizable()
                         .frame(width: 20, height: 20)
                         .padding()
                         .background(Color.white)
                         .foregroundColor(.gray)
                         .cornerRadius(15)
                 }

                 // 标准 / 卫星
                 Button {
                     isSatelliteMode.toggle()
                     updateMapStyle()
                 } label: {
                     Image(systemName: isSatelliteMode ? "map.fill" : "map")
                         .resizable()
                         .frame(width: 20, height: 20)
                         .padding()
                         .background(Color.white)
                         .foregroundColor(.gray)
                         .cornerRadius(15)
                 }
             }
             .padding(.trailing, 16)
             .padding(.bottom, 50)
             Spacer()
         }
         .frame(maxWidth: .infinity, alignment: .trailing)
     }

     // MARK: - 定位权限（只负责让蓝点能出现）
     private func ensureMapAuthorization() {
         let status = authLM.authorizationStatus
         switch status {
         case .notDetermined:
             authLM.requestWhenInUseAuthorization()
         case .authorizedAlways, .authorizedWhenInUse:
             break
         case .denied, .restricted:
             break
         @unknown default:
             break
         }
     }

     // MARK: - 与原版一致的地图更新方法
     private func updateMapViewMode() {
         guard let mapView = self.mapView else { return }
         // 按当前中心切换 2D/3D
         let camera = MKMapCamera(
             lookingAtCenter: mapView.centerCoordinate,
             fromDistance: is3DMode ? 1000 : 3000,
             pitch: is3DMode ? 45 : 0,
             heading: mapView.camera.heading
         )
         mapView.setCamera(camera, animated: true)
     }

     private func updateMapStyle() {
         guard let mapView = self.mapView else { return }
         // 与原代码相同的简洁实现
         mapView.mapType = isSatelliteMode ? .satelliteFlyover : .standard
         mapView.isZoomEnabled = true
         mapView.isScrollEnabled = true
         mapView.isRotateEnabled = true
         mapView.isPitchEnabled = true
     }
 }

 */


/*
 12.30
 import SwiftUI
 import MapboxMaps
 import CoreLocation
 import Snap

 struct RecordingView: View {
     // MARK: - Map 状态
     @State private var mapView: MapView?

     /// 现在只保留你在 Mapbox Studio 做的那一个样式
     /// 确保 RecordingMapStyle.contour 的 styleURI 是你的自定义链接
     private let mapStyle: RecordingMapStyle = .contour

     // 结束流程遮罩
     @State private var isEnding = false
     @State private var showMap = true

     // 总结数据
     @State private var summaryToPresent: SessionSummary? = nil

     // 用于定位授权（只为了让系统允许定位，蓝点由 Mapbox 自己管）
     private let authLM = CLLocationManager()

     // 只在第一次创建 MapView 时设置相机
     @State private var didSetInitialCamera = false

     var body: some View {
         ZStack {
             // 地图
             if showMap {
                 MapBlock
             }

             // 底部抽屉 Recents
             ControlBlock
                 .allowsHitTesting(!isEnding)
                 .opacity(isEnding ? 0.4 : 1)

             // 结束遮罩
             if isEnding {
                 Color.black.opacity(0.001).ignoresSafeArea()
                 ProgressView("保存中…")
                     .padding()
                     .background(.thinMaterial)
                     .clipShape(RoundedRectangle(cornerRadius: 12))
             }
         }
         .onAppear {
             didSetInitialCamera = false
             ensureMapAuthorization()
         }
         // 结束后展示总结
         .fullScreenCover(item: $summaryToPresent) { s in
             SessionSummaryScreen(summary: s) {
                 summaryToPresent = nil
                 isEnding = false
                 showMap = true
                 mapView?.isUserInteractionEnabled = true
             }
         }
     }

     // MARK: - MapBlock

     private var MapBlock: some View {
         MapViewRepresentable(style: mapStyle) { map in
             DispatchQueue.main.async {
                 self.mapView = map
                 configureInitialCameraIfNeeded()
             }
         }
         .ignoresSafeArea()
     }

     /// 仅在 MapView 创建后第一次设置相机
     private func configureInitialCameraIfNeeded() {
         guard !didSetInitialCamera, let map = mapView else { return }
         didSetInitialCamera = true

         // 尝试用系统当前定位作为初始中心点
         let coord = authLM.location?.coordinate

         let camera: CameraOptions
         if let c = coord {
             camera = CameraOptions(
                 center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                 zoom: 17,          // 这个缩放就是你之前测出来能看到雪道名字的范围
                 bearing: 0,
                 pitch: 0           // 现在只有一种样式，就保持俯视；想要倾斜可以改成 30 或 45
             )
         } else {
             // 拿不到定位就给一个全球缩放作为兜底
             camera = CameraOptions(
                 center: nil,
                 zoom: 2
             )
         }

         map.mapboxMap.setCamera(to: camera)
     }

     // MARK: - 控制抽屉（Recents）

     private var ControlBlock: some View {
         VStack(spacing: 0) {
             Spacer()
             SnapDrawer(
                 large: .paddingToTop(500),
                 medium: .fraction(0.4),
                 tiny: .height(100),
                 allowInvisible: false
             ) { state in
                 ZStack(alignment: .topTrailing) {
                     Recents(
                         onWillStop: { [weakMap = mapView] in
                             // 开始结束流程：禁止地图交互，隐藏地图
                             isEnding = true
                             weakMap?.isUserInteractionEnabled = false
                             showMap = false
                         },
                         onSummary: { s in
                             // 存好总结，交给 fullScreenCover 展示
                             summaryToPresent = s
                         }
                     )
                     .opacity(state == .tiny || isEnding ? 0 : 1)
                     .allowsHitTesting(state != .tiny && !isEnding)
                     .padding(.horizontal, 16)
                     .padding(.top, 24)
                     .padding(.bottom, 12)
                 }
             }
         }
     }

     // MARK: - 定位权限（让 Mapbox 能拿到系统定位）

     private func ensureMapAuthorization() {
         let status = authLM.authorizationStatus
         switch status {
         case .notDetermined:
             authLM.requestWhenInUseAuthorization()
         case .authorizedAlways, .authorizedWhenInUse:
             break
         case .denied, .restricted:
             // 用户关了就先这样，不强行处理
             break
         @unknown default:
             break
         }
     }
 }

 
 */
