import SwiftUI

public struct NodeDetailsView: View {
    let nodeId: String
    let treeViewModel: TreeViewModel?
    let embeddedMode: Bool

    public init(nodeId: String, treeViewModel: TreeViewModel? = nil, embeddedMode: Bool = false) {
        self.nodeId = nodeId
        self.treeViewModel = treeViewModel
        self.embeddedMode = embeddedMode
    }

    public var body: some View {
        #if os(iOS)
        NodeDetailsView_iOS(nodeId: nodeId, treeViewModel: treeViewModel, embeddedMode: embeddedMode)
        #else
        NodeDetailsView_macOS(nodeId: nodeId, treeViewModel: treeViewModel, embeddedMode: embeddedMode)
        #endif
    }
}