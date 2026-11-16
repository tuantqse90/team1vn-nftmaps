import Foundation

/// Style MapLibre vẽ bản đồ thật (vector tile OpenMapTiles) theo bảng màu "BẢN ĐỒ" của design PawRun:
/// nền cỏ, đường kem viền vàng, sông xanh ngọc, công viên xanh đậm, nhà khối pastel nổi 3D.
enum PawMapStyle {
    /// Nguồn tile: NullMaps tự host (Simulator / mạng nhà), không thì OpenFreeMap (miễn phí, cùng schema).
    struct TileSource {
        let tiles: [String]?
        let tileJSON: String?
        let glyphs: String
        let font: String
        let attribution: String
    }

    static var source: TileSource {
        if let base = Config.nullMapsURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
           usable(base) {
            return TileSource(tiles: ["\(base)/tiles/vietnam/{z}/{x}/{y}?v=z16"], tileJSON: nil,
                              glyphs: "\(base)/tiles/font/{fontstack}/{range}", font: "Noto Sans Bold",
                              attribution: "© OpenStreetMap · NullMaps")
        }
        return TileSource(tiles: nil, tileJSON: "https://tiles.openfreemap.org/planet",
                          glyphs: "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf", font: "Noto Sans Bold",
                          attribution: "© OpenStreetMap · OpenFreeMap")
    }

    /// 127.0.0.1 chỉ trỏ về máy Mac khi chạy Simulator; trên iPhone thật thì dùng nguồn công khai.
    private static func usable(_ base: String) -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return !(base.contains("127.0.0.1") || base.contains("localhost"))
        #endif
    }

    // Bảng màu (Styleguide · BẢN ĐỒ + artboard Bản đồ)
    static let grass = "#C3EA96"
    static let block = "#B6E289"
    static let park = "#8FD068"
    static let parkEdge = "#E2F3C4"
    static let water = "#5FCAD9"
    static let waterEdge = "#A6E8EE"
    static let road = "#FFF6DD"
    static let roadEdge = "#E3CF9C"
    static let roadDash = "#F0DCA4"
    static let roadLabel = "#B39758"
    static let parkLabel = "#2F6A1F"
    static let route = "#FF7A1A"
    static let buildings = ["#FFC6A3", "#FFE08A", "#C2DAFF", "#FBF6EA"]

    static func json() -> Data {
        let src = source
        var vector: [String: Any] = ["type": "vector", "attribution": src.attribution]
        if let tiles = src.tiles {
            vector["tiles"] = tiles
            vector["minzoom"] = 0
            vector["maxzoom"] = 16
        } else if let url = src.tileJSON {
            vector["url"] = url
        }
        let emptyGeoJSON: [String: Any] = ["type": "geojson", "data": ["type": "FeatureCollection", "features": []]]
        let style: [String: Any] = [
            "version": 8,
            "name": "PawRun",
            "glyphs": src.glyphs,
            "sources": [
                "omt": vector,
                "range": emptyGeoJSON, "suggested": emptyGeoJSON, "track": emptyGeoJSON,
                "rings": emptyGeoJSON, "me": emptyGeoJSON,
            ],
            "layers": layers(font: src.font),
            // Ánh sáng dịu từ phía trước: mặt bên khối nhà chỉ sẫm nhẹ như design (không đen).
            "light": ["anchor": "viewport", "color": "#FFFFFF", "intensity": 0.18, "position": [1.15, 200, 35]],
        ]
        return (try? JSONSerialization.data(withJSONObject: style)) ?? Data()
    }

    private static func zoomWidths(_ stops: [(Double, [String: Double], Double)]) -> [Any] {
        // Mỗi mốc zoom: độ rộng theo loại đường (match class) — zoom phải là biểu thức ngoài cùng.
        var expression: [Any] = ["interpolate", ["exponential", 1.6], ["zoom"]]
        for (zoom, byClass, fallback) in stops {
            var match: [Any] = ["match", ["get", "class"]]
            for (classes, width) in byClass.sorted(by: { $0.key < $1.key }) {
                match.append(classes.split(separator: ",").map(String.init))
                match.append(width)
            }
            match.append(fallback)
            expression.append(zoom)
            expression.append(match)
        }
        return expression
    }

    private static func roadWidth(extra: Double) -> [Any] {
        zoomWidths([
            (13, ["motorway,trunk,primary": 2.5 + extra * 0.4, "secondary,tertiary": 1.6 + extra * 0.4], 0.8 + extra * 0.3),
            (15, ["motorway,trunk,primary": 8 + extra, "secondary,tertiary": 5.5 + extra], 3 + extra * 0.7),
            (17, ["motorway,trunk,primary": 24 + extra * 2, "secondary,tertiary": 17 + extra * 2], 11 + extra * 1.5),
            (19, ["motorway,trunk,primary": 70 + extra * 4, "secondary,tertiary": 52 + extra * 4], 34 + extra * 3),
        ])
    }

    private static var drivable: [Any] { ["match", ["get", "class"],
                                          ["motorway", "trunk", "primary", "secondary", "tertiary", "minor", "service",
                                           "residential", "living_street", "unclassified", "pedestrian"], true, false] }

    private static func layers(font: String) -> [[String: Any]] {
        [
            ["id": "background", "type": "background", "paint": ["background-color": grass]],
            ["id": "blocks", "type": "fill", "source": "omt", "source-layer": "landuse",
             "filter": ["match", ["get", "class"], ["residential", "commercial", "retail", "industrial", "school"], true, false],
             "paint": ["fill-color": block]],
            ["id": "green", "type": "fill", "source": "omt", "source-layer": "landcover",
             "filter": ["match", ["get", "class"], ["grass", "wood", "park", "farmland"], true, false],
             "paint": ["fill-color": park, "fill-opacity": 0.9]],
            ["id": "park", "type": "fill", "source": "omt", "source-layer": "park",
             "paint": ["fill-color": park, "fill-outline-color": parkEdge]],
            ["id": "park-edge", "type": "line", "source": "omt", "source-layer": "park", "minzoom": 15,
             "paint": ["line-color": parkEdge, "line-width": 3, "line-opacity": 0.9]],
            ["id": "water-edge", "type": "line", "source": "omt", "source-layer": "water",
             "paint": ["line-color": waterEdge, "line-width": ["interpolate", ["linear"], ["zoom"], 13, 2, 18, 10]]],
            ["id": "water", "type": "fill", "source": "omt", "source-layer": "water",
             "paint": ["fill-color": water]],
            ["id": "waterway", "type": "line", "source": "omt", "source-layer": "waterway",
             "paint": ["line-color": water, "line-width": ["interpolate", ["linear"], ["zoom"], 13, 1.5, 18, 9]]],
            ["id": "path", "type": "line", "source": "omt", "source-layer": "transportation",
             "filter": ["match", ["get", "class"], ["path", "track"], true, false], "minzoom": 15,
             "layout": ["line-cap": "round"],
             "paint": ["line-color": road, "line-width": ["interpolate", ["linear"], ["zoom"], 15, 1.5, 18, 5]]],
            ["id": "road-casing", "type": "line", "source": "omt", "source-layer": "transportation",
             "filter": drivable, "layout": ["line-cap": "round", "line-join": "round"],
             "paint": ["line-color": roadEdge, "line-width": roadWidth(extra: 4)]],
            ["id": "road", "type": "line", "source": "omt", "source-layer": "transportation",
             "filter": drivable, "layout": ["line-cap": "round", "line-join": "round"],
             "paint": ["line-color": road, "line-width": roadWidth(extra: 0)]],
            ["id": "road-dash", "type": "line", "source": "omt", "source-layer": "transportation", "minzoom": 15,
             "filter": ["match", ["get", "class"], ["motorway", "trunk", "primary"], true, false],
             "paint": ["line-color": roadDash, "line-width": 2, "line-dasharray": [5, 4]]],
            ["id": "range-fill", "type": "fill", "source": "range",
             "paint": ["fill-color": route, "fill-opacity": 0.10]],
            ["id": "range-line", "type": "line", "source": "range",
             "paint": ["line-color": route, "line-opacity": 0.6, "line-width": 3, "line-dasharray": [3, 2.4]]],
            ["id": "suggested-halo", "type": "line", "source": "suggested",
             "layout": ["line-cap": "round", "line-join": "round"],
             "paint": ["line-color": route, "line-opacity": 0.22, "line-width": 14]],
            ["id": "suggested", "type": "line", "source": "suggested",
             "layout": ["line-cap": "round", "line-join": "round"],
             "paint": ["line-color": route, "line-width": 6, "line-dasharray": [0.1, 2.2]]],
            ["id": "track-halo", "type": "line", "source": "track",
             "layout": ["line-cap": "round", "line-join": "round"],
             "paint": ["line-color": route, "line-opacity": 0.25, "line-width": 16]],
            ["id": "track", "type": "line", "source": "track",
             "layout": ["line-cap": "round", "line-join": "round"],
             "paint": ["line-color": route, "line-width": 7]],
            ["id": "rings", "type": "circle", "source": "rings",
             "paint": ["circle-pitch-alignment": "map",
                       "circle-radius": ["interpolate", ["linear"], ["zoom"], 15, 9, 17, 18, 19, 40],
                       "circle-color": ["get", "color"], "circle-opacity": 0.22,
                       "circle-stroke-color": ["get", "color"], "circle-stroke-width": 3]],
            ["id": "me", "type": "circle", "source": "me",
             "paint": ["circle-pitch-alignment": "map",
                       "circle-radius": ["interpolate", ["linear"], ["zoom"], 15, 12, 17, 24, 19, 52],
                       "circle-color": "#FFFFFF", "circle-opacity": 0.55,
                       "circle-stroke-color": route, "circle-stroke-width": 4]],
            ["id": "buildings", "type": "fill-extrusion", "source": "omt", "source-layer": "building", "minzoom": 14,
             "paint": [
                "fill-extrusion-color": ["match", ["%", ["to-number", ["id"], 0], 4],
                                         0, buildings[0], 1, buildings[1], 2, buildings[2], buildings[3]],
                // Khối thấp kiểu đồ chơi (design): 3–7 m dù nhà thật cao bao nhiêu.
                "fill-extrusion-height": ["min", ["+", 3, ["*", ["coalesce", ["get", "render_height"], 6], 0.12]], 7],
                "fill-extrusion-base": 0,
                "fill-extrusion-opacity": 0.97,
             ]],
            ["id": "road-label", "type": "symbol", "source": "omt", "source-layer": "transportation_name", "minzoom": 15,
             "layout": ["symbol-placement": "line", "text-field": ["coalesce", ["get", "name:vi"], ["get", "name"]],
                        "text-font": [font], "text-size": ["interpolate", ["linear"], ["zoom"], 15, 10, 18, 14],
                        "text-letter-spacing": 0.18, "text-transform": "uppercase", "text-max-angle": 30],
             "paint": ["text-color": roadLabel, "text-halo-color": road, "text-halo-width": 2]],
            ["id": "park-label", "type": "symbol", "source": "omt", "source-layer": "park", "minzoom": 15,
             "filter": ["has", "name"],
             "layout": ["text-field": ["get", "name"], "text-font": [font], "text-size": 15, "text-max-width": 8],
             "paint": ["text-color": parkLabel, "text-halo-color": parkEdge, "text-halo-width": 1.5]],
        ]
    }
}
