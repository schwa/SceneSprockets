import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("1. Sphere", systemImage: "circle.fill") {
                Tutorial1Sphere()
            }
            Tab("2. Hierarchy & Camera", systemImage: "point.3.connected.trianglepath.dotted") {
                Tutorial2Hierarchy()
            }
            Tab("3. Lights", systemImage: "lightbulb") {
                Tutorial3Lights()
            }
            Tab("4. Actions", systemImage: "play") {
                Tutorial4Actions()
            }
            Tab("5. Constraints", systemImage: "scope") {
                Tutorial5Constraints()
            }
        }
    }
}

#Preview {
    ContentView()
}
