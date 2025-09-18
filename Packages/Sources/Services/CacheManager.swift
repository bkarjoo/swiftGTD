import Foundation
import Models
import Core

/// Manages local cache storage for offline functionality
@MainActor
public class CacheManager {
    public static let shared = CacheManager()
    private let logger = Logger.shared
    
    // Cache file names
    private let nodesCacheFile = "nodes_cache.json"
    private let tagsCacheFile = "tags_cache.json"
    private let rulesCacheFile = "rules_cache.json"
    private let metadataCacheFile = "cache_metadata.json"
    
    // Cache metadata
    public struct CacheMetadata: Codable {
        let lastSyncDate: Date
        let nodeCount: Int
        let tagCount: Int
        let ruleCount: Int
        let userId: String?
    }
    
    // Cleanup result
    public struct MaintenanceResult {
        public let filesRemoved: Int
        public let bytesFreed: Int64
    }
    
    // Auto-cleanup threshold
    private var autoCleanupThresholdBytes: Int64 = 10 * 1024 * 1024 // Default 10MB
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private init() {
        logger.log("📦 CacheManager initialized", category: "CacheManager")
        ensureCacheDirectoryExists()
    }
    
    private nonisolated func ensureCacheDirectoryExists() {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheDir = documentsDir.appendingPathComponent("Cache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            Logger.shared.log("📁 Created cache directory", category: "CacheManager")
        }
    }

    private nonisolated func cacheURL(for filename: String) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent(filename)
    }
    
    // MARK: - Save Methods
    
    /// Save all nodes to cache
    public func saveNodes(_ nodes: [Node]) async {
        let nodesCacheFile = self.nodesCacheFile
        await Task.detached(priority: .background) { [nodesCacheFile] in
            do {
                self.ensureCacheDirectoryExists()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(nodes)
                let url = self.cacheURL(for: nodesCacheFile)
                try data.write(to: url)
                Logger.shared.log("💾 Cached \(nodes.count) nodes (\(data.count) bytes)", category: "CacheManager")
            } catch {
                Logger.shared.log("❌ Failed to cache nodes: \(error)", level: .error, category: "CacheManager")
            }
        }.value

        // Check if auto-cleanup needed after save
        await checkAndPerformAutoCleanup()
    }
    
    /// Save all tags to cache
    public func saveTags(_ tags: [Tag]) async {
        let tagsCacheFile = self.tagsCacheFile
        await Task.detached(priority: .background) { [tagsCacheFile] in
            do {
                self.ensureCacheDirectoryExists()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(tags)
                let url = self.cacheURL(for: tagsCacheFile)
                try data.write(to: url)
                Logger.shared.log("💾 Cached \(tags.count) tags", category: "CacheManager")
            } catch {
                Logger.shared.log("❌ Failed to cache tags: \(error)", level: .error, category: "CacheManager")
            }
        }.value
    }
    
    /// Save all rules to cache
    public func saveRules(_ rules: [Rule]) async {
        let rulesCacheFile = self.rulesCacheFile
        await Task.detached(priority: .background) { [rulesCacheFile] in
            do {
                self.ensureCacheDirectoryExists()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(rules)
                let url = self.cacheURL(for: rulesCacheFile)
                try data.write(to: url)
                Logger.shared.log("💾 Cached \(rules.count) rules", category: "CacheManager")
            } catch {
                Logger.shared.log("❌ Failed to cache rules: \(error)", level: .error, category: "CacheManager")
            }
        }.value
    }
    
    /// Save cache metadata
    public func saveMetadata(nodeCount: Int, tagCount: Int, ruleCount: Int) async {
        let metadata = CacheMetadata(
            lastSyncDate: Date(),
            nodeCount: nodeCount,
            tagCount: tagCount,
            ruleCount: ruleCount,
            userId: UserDefaults.standard.string(forKey: "user_id")
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metadata)
            let url = cacheURL(for: metadataCacheFile)
            try data.write(to: url)
            logger.log("💾 Saved cache metadata", category: "CacheManager")
        } catch {
            logger.log("❌ Failed to save metadata: \(error)", level: .error, category: "CacheManager")
        }
    }
    
    // MARK: - Load Methods
    
    /// Load all nodes from cache
    public func loadNodes() async -> [Node]? {
        let nodesCacheFile = self.nodesCacheFile
        return await Task.detached(priority: .background) {
            let nodesCacheFile = nodesCacheFile
            let url = self.cacheURL(for: nodesCacheFile)

            guard FileManager.default.fileExists(atPath: url.path) else {
                Logger.shared.log("📦 No nodes cache found", category: "CacheManager")
                return nil
            }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let nodes = try decoder.decode([Node].self, from: data)
                Logger.shared.log("📦 Loaded \(nodes.count) nodes from cache", category: "CacheManager")
                return nodes
            } catch {
                Logger.shared.log("❌ Failed to load nodes from cache: \(error)", level: .error, category: "CacheManager")
                return nil
            }
        }.value
    }
    
    /// Load all tags from cache
    public func loadTags() async -> [Tag]? {
        let tagsCacheFile = self.tagsCacheFile
        return await Task.detached(priority: .background) {
            let tagsCacheFile = tagsCacheFile
            let url = self.cacheURL(for: tagsCacheFile)

            guard FileManager.default.fileExists(atPath: url.path) else {
                Logger.shared.log("📦 No tags cache found", category: "CacheManager")
                return nil
            }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let tags = try decoder.decode([Tag].self, from: data)
                Logger.shared.log("📦 Loaded \(tags.count) tags from cache", category: "CacheManager")
                return tags
            } catch {
                Logger.shared.log("❌ Failed to load tags from cache: \(error)", level: .error, category: "CacheManager")
                return nil
            }
        }.value
    }
    
    /// Load all rules from cache
    public func loadRules() async -> [Rule]? {
        let rulesCacheFile = self.rulesCacheFile
        return await Task.detached(priority: .background) {
            let rulesCacheFile = rulesCacheFile
            let url = self.cacheURL(for: rulesCacheFile)

            guard FileManager.default.fileExists(atPath: url.path) else {
                Logger.shared.log("📦 No rules cache found", category: "CacheManager")
                return nil
            }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let rules = try decoder.decode([Rule].self, from: data)
                Logger.shared.log("📦 Loaded \(rules.count) rules from cache", category: "CacheManager")
                return rules
            } catch {
                Logger.shared.log("❌ Failed to load rules from cache: \(error)", level: .error, category: "CacheManager")
                return nil
            }
        }.value
    }
    
    /// Load cache metadata
    public func loadMetadata() async -> CacheMetadata? {
        let url = cacheURL(for: metadataCacheFile)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.log("📦 No cache metadata found", category: "CacheManager")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(CacheMetadata.self, from: data)
            logger.log("📦 Cache last synced: \(metadata.lastSyncDate)", category: "CacheManager")
            return metadata
        } catch {
            logger.log("❌ Failed to load metadata: \(error)", level: .error, category: "CacheManager")
            return nil
        }
    }
    
    // MARK: - Cache Management
    
    /// Clear all cached data
    public func clearCache() async {
        let cacheDir = documentsDirectory.appendingPathComponent("Cache", isDirectory: true)
        try? FileManager.default.removeItem(at: cacheDir)
        ensureCacheDirectoryExists()
        logger.log("🗑️ Cache cleared", category: "CacheManager")
    }
    
    /// Get cache size in bytes
    public func getCacheSize() async -> Int64 {
        let cacheDir = documentsDirectory.appendingPathComponent("Cache", isDirectory: true)
        
        guard let enumerator = FileManager.default.enumerator(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        
        return totalSize
    }
    
    /// Format bytes to human readable string
    public func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Cleanup Methods
    
    /// Remove cache files older than specified number of days
    /// - Parameter olderThanDays: Age threshold in days
    /// - Returns: Number of files removed
    public func cleanupOldFiles(olderThanDays days: Int) async -> Int {
        let cacheDir = documentsDirectory.appendingPathComponent("Cache", isDirectory: true)
        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 3600))
        var removedCount = 0
        
        // Protected files that should not be deleted based on age
        let protectedFiles = Set([metadataCacheFile])
        
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .nameKey]
        ) else {
            logger.log("⚠️ Could not enumerate cache directory", level: .warning, category: "CacheManager")
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            
            // Skip protected files
            if protectedFiles.contains(filename) {
                continue
            }
            
            do {
                let attributes = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                if let modDate = attributes.contentModificationDate,
                   modDate < cutoffDate {
                    try FileManager.default.removeItem(at: fileURL)
                    removedCount += 1
                    logger.log("🗑️ Removed old cache file: \(filename)", category: "CacheManager")
                }
            } catch {
                logger.log("❌ Error processing cache file \(filename): \(error)", 
                          level: .error, category: "CacheManager")
            }
        }
        
        if removedCount > 0 {
            logger.log("🧹 Cleaned up \(removedCount) old cache files", category: "CacheManager")
        }
        
        return removedCount
    }
    
    /// Enforce maximum cache size by removing oldest files
    /// - Parameter maxBytes: Maximum cache size in bytes
    /// - Returns: List of removed file names
    public func enforceMaxCacheSize(maxBytes: Int64) async -> [String] {
        let cacheDir = documentsDirectory.appendingPathComponent("Cache", isDirectory: true)
        var removedFiles: [String] = []
        
        // Get all cache files with their sizes and dates
        var cacheFiles: [(url: URL, size: Int64, date: Date)] = []
        
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else {
            return removedFiles
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let attributes = try fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                )
                if let size = attributes.fileSize,
                   let date = attributes.contentModificationDate {
                    cacheFiles.append((url: fileURL, size: Int64(size), date: date))
                }
            } catch {
                logger.log("❌ Error reading file attributes: \(error)", 
                          level: .error, category: "CacheManager")
            }
        }
        
        // Sort by date, oldest first
        cacheFiles.sort { $0.date < $1.date }
        
        // Calculate total size
        let totalSize = cacheFiles.reduce(0) { $0 + $1.size }
        
        if totalSize <= maxBytes {
            return removedFiles // Already under limit
        }
        
        // Remove oldest files until under limit
        var currentSize = totalSize
        for file in cacheFiles {
            if currentSize <= maxBytes {
                break
            }
            
            // Skip critical files
            let filename = file.url.lastPathComponent
            if filename == nodesCacheFile || filename == metadataCacheFile {
                continue // Try to preserve critical files
            }
            
            do {
                try FileManager.default.removeItem(at: file.url)
                currentSize -= file.size
                removedFiles.append(filename)
                logger.log("🗑️ Removed \(filename) to enforce size limit", category: "CacheManager")
            } catch {
                logger.log("❌ Error removing file \(filename): \(error)", 
                          level: .error, category: "CacheManager")
            }
        }
        
        let freedBytes = totalSize - currentSize
        logger.log("📏 Enforced cache size limit: freed \(formatBytes(freedBytes))", category: "CacheManager")
        
        return removedFiles
    }
    
    /// Perform cache maintenance with age and size constraints
    /// - Parameters:
    ///   - maxAgeInDays: Maximum age for cache files
    ///   - maxSizeInMB: Maximum total cache size in megabytes
    /// - Returns: Maintenance result with statistics
    public func performMaintenance(maxAgeInDays: Int, maxSizeInMB: Double) async -> MaintenanceResult {
        let initialSize = await getCacheSize()
        
        // First remove old files
        let filesRemovedByAge = await cleanupOldFiles(olderThanDays: maxAgeInDays)
        
        // Then enforce size limit
        let maxBytes = Int64(maxSizeInMB * 1024 * 1024)
        let filesRemovedBySize = await enforceMaxCacheSize(maxBytes: maxBytes)
        
        let finalSize = await getCacheSize()
        let bytesFreed = max(0, initialSize - finalSize)
        
        let totalFilesRemoved = filesRemovedByAge + filesRemovedBySize.count
        
        logger.log("🧹 Maintenance complete: removed \(totalFilesRemoved) files, freed \(formatBytes(bytesFreed))",
                  category: "CacheManager")
        
        return MaintenanceResult(filesRemoved: totalFilesRemoved, bytesFreed: bytesFreed)
    }
    
    /// Set auto-cleanup threshold
    /// - Parameter kilobytes: Threshold in kilobytes
    public func setAutoCleanupThreshold(kilobytes: Int) async {
        autoCleanupThresholdBytes = Int64(kilobytes * 1024)
        logger.log("⚙️ Auto-cleanup threshold set to \(kilobytes)KB", category: "CacheManager")
    }
    
    /// Check if auto-cleanup should run and execute if needed
    private func checkAndPerformAutoCleanup() async {
        let currentSize = await getCacheSize()
        if currentSize > autoCleanupThresholdBytes {
            logger.log("🔄 Auto-cleanup triggered (size: \(formatBytes(currentSize)))", category: "CacheManager")
            _ = await enforceMaxCacheSize(maxBytes: autoCleanupThresholdBytes)
        }
    }
}