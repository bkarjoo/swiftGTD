import SwiftUI

public struct NodeDetailsView: View {
    let nodeId: String
    let treeViewModel: TreeViewModel?

    public init(nodeId: String, treeViewModel: TreeViewModel? = nil) {
        self.nodeId = nodeId
        self.treeViewModel = treeViewModel
    }

    public var body: some View {
        #if os(iOS)
        NodeDetailsView_iOS(nodeId: nodeId, treeViewModel: treeViewModel)
        #else
        NodeDetailsView_macOS(nodeId: nodeId, treeViewModel: treeViewModel)
        #endif
    }
}