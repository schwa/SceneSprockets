import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("1. Sphere", systemImage: "circle.fill") {
                Tutorial1Sphere()
            }
            Tab("2. Lights", systemImage: "lightbulb") {
                Tutorial2Lights()
            }
            Tab("3. Hierarchy", systemImage: "point.3.connected.trianglepath.dotted") {
                Tutorial3Hierarchy()
            }
            Tab("4. Actions", systemImage: "play") {
                Tutorial4Actions()
            }
            Tab("5. Constraints", systemImage: "scope") {
                Tutorial5Constraints()
            }
            Tab("6. Atmosphere", systemImage: "cloud.fog") {
                Tutorial6Atmosphere()
            }
        }
    }
}

#Preview {
    ContentView()
}
