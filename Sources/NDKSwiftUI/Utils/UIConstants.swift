import NDKSwift

/// UI-related constants for consistent layout and styling across NDKSwiftUI components
public enum UIConstants {
    // MARK: - Profile Picture Sizes
    
    /// Standard profile picture sizes
    public enum ProfilePictureSize {
        /// Small profile picture (40 points)
        public static let small: CGFloat = 40
        /// Medium profile picture (60 points)
        public static let medium: CGFloat = 60
        /// Large profile picture (80 points)
        public static let large: CGFloat = 80
        /// Extra large profile picture (120 points)
        public static let extraLarge: CGFloat = 120
    }
    
    // MARK: - Image Display
    
    /// Maximum height for images in markdown content
    public static let markdownImageMaxHeight: CGFloat = 300
    
    // MARK: - Zap Button
    
    /// Standard zap amounts in satoshis
    /// These reference the core amount definitions for consistency
    public enum ZapAmounts {
        /// Small zap amounts for quick interactions
        public static let small = [100, 500, 1000]
        /// Standard zap amounts for general use - references core definition
        public static let standard = AmountPresets.standardAmounts
        /// Extended zap amounts including larger values - references core definition
        public static let extended = AmountPresets.extendedAmounts
    }
    
    // MARK: - Event View
    
    /// Thumbnail dimensions for media previews
    public enum MediaThumbnail {
        public static let width: CGFloat = 60
        public static let height: CGFloat = 40
    }
    
    /// Maximum content height for different event types
    public enum MaxContentHeight {
        /// Default maximum height for most content
        public static let `default`: CGFloat = 300
        /// Extended height for longer content
        public static let extended: CGFloat = 500
        /// Unlimited height (no restriction)
        public static let unlimited: CGFloat = .infinity
    }
    
    /// Image heights for different event view styles
    public enum EventImageHeight {
        /// Compact view image height
        public static let compact: CGFloat = 150
        /// Embedded view image height
        public static let embedded: CGFloat = 200
        /// Default/full view image height
        public static let `default`: CGFloat = 300
    }
}