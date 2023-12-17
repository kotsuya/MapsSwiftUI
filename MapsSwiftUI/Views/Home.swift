//
//  Home.swift
//  MapsSwiftUI
//
//  Created by Yoo on 2023/12/15.
//

import SwiftUI
import MapKit

struct Home: View {
    // Map Properties
    @State private var cameraPosition: MapCameraPosition = .region(.myRegion)
    @State private var mapSelection: MKMapItem?
    @Namespace private var locationSpace
    @State private var viewingRegion: MKCoordinateRegion?
    
    // Search Properties
    @State private var searchText: String = ""
    @State private var showSearch: Bool = false
    @State private var searchResults: [MKMapItem] = []
    
    // Map Selection Detail Properties
    @State private var showDetails: Bool = false
    @State private var lookAroundScene: MKLookAroundScene?
    
    // Route Properties
    @State private var routeDisplaying: Bool = false
    @State private var route: MKRoute?
    @State private var routeDestination: MKMapItem?
    
    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition, selection: $mapSelection, scope: locationSpace) {
                Annotation("Apple Park", coordinate: .myLocation) {
                    ZStack {
                        Image(systemName: "applelogo")
                            .font(.title3)
                        Image(systemName: "square")
                            .font(.largeTitle)
                    }
                }
                .annotationTitles(.hidden)
                
                // Simply Display Annotations as Marker, as we seen before
                ForEach(searchResults, id: \.self) { item in
                    if routeDisplaying {
                        if item == routeDestination {
                            let placemark = item.placemark
                            Marker(placemark.name ?? "Place", coordinate: placemark.coordinate)
                        } else {
                            let placemark = item.placemark
                            Marker(placemark.name ?? "Place", coordinate: placemark.coordinate)
                        }
                    }
                }
                
                // Display Route using Polyline
                if let route {
                    MapPolyline(route.polyline)
                    // Applying Bigger Storke
                        .stroke(.blue, lineWidth: 7)
                }
                
                // To Show User Current Location
                UserAnnotation()
            }
            .onMapCameraChange({ ctx in
                viewingRegion = ctx.region
            })
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 15) {
                    MapCompass(scope: locationSpace)
                    MapPitchToggle(scope: locationSpace)
                    MapUserLocationButton(scope: locationSpace)
                }
                .buttonBorderShape(.circle)
                .padding()
            }
            .mapScope(locationSpace)
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            // Search bar
            .searchable(text: $searchText, isPresented: $showSearch)
            // Showing Translucent Toolbar
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            // When Route Displaying Hiding Top And Bottom Bar
            .toolbar(routeDisplaying ? .hidden : .visible, for: .navigationBar)
            .sheet(isPresented: $showDetails, onDismiss: {
                withAnimation(.snappy) {
                    // Zooming Region
                    if let boundingRect = route?.polyline.boundingMapRect, routeDisplaying {
                        cameraPosition = .rect(boundingRect)
                    }
                }
            }, content: {
                MapDetails()
                    .presentationDetents([.height(300)])
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(300)))
                    .presentationCornerRadius(25)
                    .interactiveDismissDisabled(true)
            })
            .safeAreaInset(edge: .bottom) {
                if routeDisplaying {
                    Button {
                        // Closing The Route and Setting the Selection
                        withAnimation(.snappy) {
                            routeDisplaying = false
                            showDetails = true
                            mapSelection = routeDestination
                            routeDestination = nil
                            route = nil
                            cameraPosition = .region(.myRegion)
                        }
                    } label: {
                        Text("End Route")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.gradient, in: .rect(cornerRadius:15))
                            .padding()
                            .background {.ultraThinMaterial}
                    }

                }
            }
        }
        .onSubmit(of: .search) {
            Task {
                guard !searchText.isEmpty else { return }
                await searchPlaces()
            }
        }
        .onChange(of: showSearch, initial: false) {
            if !showSearch {
                // Clearing Search Results
                searchResults.removeAll(keepingCapacity: false)
                showDetails = false
                
                // Zooming out to User Region when Search Cancelled
                withAnimation(.snappy) {
                    cameraPosition = .region(.myRegion)
                }
            }
        }
        .onChange(of: mapSelection) { oldValue, newValue in
            // Displaying Details about the Selected Place
            showDetails = newValue != nil
            
            // Fetching Look Around Preview, when ever selection changes
            fetchLookAroundPreview()
        }
    }
    
    // Map Details View
    @ViewBuilder
    func MapDetails() -> some View {
        VStack(spacing: 15) {
            ZStack {
                // New Look Around API
                if lookAroundScene == nil {
                    ContentUnavailableView("No Preview Available", systemImage: "eye.slash")
                } else {
                    LookAroundPreview(scene: $lookAroundScene)
                }
            }
            .frame(height: 200)
            .clipShape(.rect(cornerRadius: 15))
            // Close Butotnx
            .overlay(alignment: .topTrailing) {
                Button {
                    showDetails = false
                    withAnimation(.snappy) {
                        mapSelection = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.black)
                        .background(.white, in: .circle)
                }
                .padding(10)

            }
            
            // Direction's Button
            Button("Get Directions") {
                fetchRoute()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.blue.gradient, in: .rect(cornerRadius: 15))
        }
        .padding(15)
    }
    
    func searchPlaces() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = viewingRegion ?? .myRegion
        
        let results = try? await MKLocalSearch(request: request).start()
        searchResults = results?.mapItems ?? []
    }
    
    // Fetching Location Preview
    func fetchLookAroundPreview() {
        if let mapSelection {
            lookAroundScene = nil
            Task {
                let request = MKLookAroundSceneRequest(mapItem: mapSelection)
                lookAroundScene = try? await request.scene
            }
        }
    }
    
    func fetchRoute() {
        if let mapSelection {
            let request = MKDirections.Request()
            request.source = .init(placemark: .init(coordinate: .myLocation))
            request.destination = mapSelection
            
            Task {
                let result = try? await MKDirections(request: request).calculate()
                route = result?.routes.first
                routeDestination = mapSelection
                
                withAnimation(.snappy) {
                    routeDisplaying = true
                    showDetails = false
                }
            }
        }
    }
}

#Preview {
    Home()
}

extension CLLocationCoordinate2D {
    static var myLocation: CLLocationCoordinate2D {
        return .init(latitude: 37.3346, longitude: -122.0090)
    }
}

extension MKCoordinateRegion {
    static var myRegion: MKCoordinateRegion {
        return .init(center: .myLocation, latitudinalMeters: 10000, longitudinalMeters: 10000)
    }
}
