Highlighter iOS App Product Specification
1. Overview and Value Proposition
Highlighter is a premium iOS application for intellectual discovery and knowledge sharing, built on the Nostr protocol with NIP-84 (kind:9802) for highlights. It empowers users to become smarter in their downtime by curating a dynamic mix of insightful content, from highlights and quotes to community discussions and personalized recommendations. The app draws from decentralized sources, ensuring censorship resistance and user ownership, while integrating Bitcoin Lightning zaps for value flows. Every interaction is designed with pixel-perfect precision to wow users, delivering an extremely polished UI that feels luxurious and intuitive from the first tap.

Target Audience: Intellectuals, lifelong learners, researchers, writers, and professionals aged 18-45 who value depth over distraction. Think: Reddit's r/books users, Kindle enthusiasts, or Notion power-users seeking a social layer.
Unique Selling Points:
Decentralized and censorship-resistant via Nostr: No central authority controls content; users own their data and identities.
Hybrid home screen: A modern blend of vertical and horizontal scrolling for a functional mix of content types, rendered with flawless animations and responsive layouts to captivate and delight.
Swarm intelligence: Public highlights overlay on original content, showing what the community finds valuable (e.g., "swarm highlights" visualizing popular passages) in a visually stunning, interactive display.
Value-enabled: Seamless zaps (micro-payments in sats) for appreciating highlights, with automatic splits to authors, curators, and highlighters, accompanied by elegant haptic feedback and ripple effects.
Cross-media support: Highlights from text, audio (timestamps), video (frame references), and more, all presented with high-fidelity thumbnails and smooth playback.
Mission Statement: Highlighter is where smart people flock to learn, share, and grow. It turns passive consumption into active enlightenment, fostering a global swarm of knowledge where value flows to those who illuminate the best ideas, all within an app that pursues pixel perfection to wow users at every turn.
Highlighter positions itself as the antithesis to short-form video apps: No algorithms pushing rage-bait; instead, serendipitous discovery of profound ideas in a calm, premium environment, with an extremely polished UI that elevates the experience to something truly remarkable.

2. Ethos, Feel, and Aesthetics
Ethos:
Intellectual Empowerment: Prioritize depth, curiosity, and community-driven curation over virality. Encourage users to "highlight the highlights" of human knowledge, inspired by concepts like purple text (Nostr's open information flow) and orange highlights (Bitcoin's value-enabled interactions).
Decentralization and Ownership: Built on Nostr, users control their private keys, data, and feeds. No ads, no data mining—pure, user-sovereign experience.
Value for Value: Integrate Lightning Network for zaps, promoting a merit-based economy where quality content and insights are rewarded directly.
Inclusivity with Excellence: Open to all, but curated for quality. Foster respectful discourse, with tools to filter noise and amplify signal.
Sustainability: Eco-friendly (low-energy Nostr relays), privacy-first, and focused on long-term user retention through genuine value.
Feel:
Modern and functional—intuitive navigation with seamless transitions between vertical and horizontal elements. Scrolling is responsive and purposeful, with haptics for delight (e.g., subtle vibration on section switches). Users feel productive, not addicted, emerging with new insights, all wrapped in an extremely polished UI that chases pixel perfection to wow at every interaction.
Serene and focused: No overwhelming notifications; users feel in control, emerging refreshed and enlightened, thanks to meticulously crafted animations and layouts.
Aesthetics:
Color Palette: Primary: Deep purple (#6A1B9A) for Nostr-inspired elements (e.g., highlights, buttons). Accent: Warm orange (#FF9500) for value flows (zaps, rewards). Neutrals: Soft grays (#F5F5F5 background), black text for readability, with optional dark mode (midnight blue accents)—all rendered with razor-sharp clarity.
Typography: Elegant sans-serif (e.g., Inter or SF Pro) for body text, with serif (e.g., Georgia) for highlighted quotes to evoke classic literature. Large, readable fonts with generous line spacing, optimized for pixel-perfect legibility across devices.
UI Style: Minimalist, card-based design with rounded corners and subtle shadows. Highlights appear as glowing orange-bordered cards in the feed. Animations: Fluid swipes, fade-ins for context overlays, and a "ripple" effect when sharing or zapping. Enhanced for hybrid layouts—cards with variable heights/widths for mixed content, all executed with an extremely polished finish to wow users.
Icons and Imagery: Clean line icons (e.g., a highlighter pen for creating, a lightbulb for discoveries). No stock photos; user-generated thumbnails from highlighted media (blurred for non-images), displayed with high-resolution precision.
Overall Vibe: Sleek like Notion's dashboard meets Spotify's personalized feeds—clean, modular, and adaptable to user preferences (e.g., customizable section order), but elevated by chasing pixel perfection in every detail to create a truly wowing experience.
3. Core Features
Highlighter's features revolve around creating, discovering, and engaging with highlights using NIP-84 events (kind:9802). All interactions are synced via Nostr relays for decentralization, with an extremely polished UI ensuring every tap and swipe feels premium and intuitive. Features build on Nostr's ecosystem, with broader integration:

Highlight Creation:
Select text from any source (imported articles, books via EPUB/PDF, web URLs, or in-app browser).
Add context (surrounding text via context tag), attribution (p tags for authors), and source (r for URLs, e/a for Nostr events).
Optional: Add personal notes or comments (comment tag for quote highlights).
Privacy: Private (local-only) or public (broadcast to relays).
Media Support: Timestamp audio/video highlights (e.g., podcast clips), with thumbnails—all presented in a sleek, pixel-perfect editor interface.
Content Types:
Highlights/Quotes: NIP-84 events (kind:9802)—text snippets with context, attributions.
Articles Liked/Zapped by Others: Aggregated from follows' zaps/likes on sources (URLs or events).
Old Articles We Liked: Personalized history—user's past zaps, saves, or interactions resurfaced.
Kind:1 Discussions: Nostr notes (kind:1) tagged #bookstr, filtered for book-related threads.
Discovery Feed:
Hybrid feeds: Vertical main scroll with embedded horizontal carousels for variety, animated with buttery-smooth transitions to wow users.
Algorithm: Transparent, user-controlled—prioritize follows, zaps, and tags; mix serendipity with personalization. No black-box ML; transparent "Why this?" explanations, displayed in elegantly designed tooltips.
Card Layout: Highlight text in bold orange, source/author below, engagement metrics (zaps, replies, shares). Swipe up/down to navigate; hold to expand for full context, with pixel-perfect responsiveness.
Filters: By topic (e.g., philosophy, science), source type (books, articles), or user (friends' highlights), accessible via a polished, intuitive sidebar.
Discovery Mechanisms:
Hybrid feeds: Vertical main scroll with embedded horizontal carousels for variety.
Algorithm: Transparent, user-controlled—prioritize follows, zaps, and tags; mix serendipity with personalization.
Swarm Highlights Overlay:
When viewing full content (e.g., an article), overlay public highlights from the community—orange underlines with popularity heatmaps (darker for more zaps/highlights), rendered with stunning visual effects.
Interactive: Tap to see who highlighted, their notes, and zap them, with haptic feedback for an immersive, wowing experience.
Social Interactions:
Zap: Send sats directly to highlighters/authors (auto-splits via Lightning Prisms), with elegant confirmation animations.
Reply/Quote: Create threaded discussions on highlights (using Nostr replies), displayed in a clean, threaded view.
Follow/Curate: Follow users for their highlight feeds; create/share collections (e.g., "Best of Stoicism"). Support follow packs (NIP-51, kind 39089)—named sets of profiles with a name, title, and image, easily shareable and importable.
Search: Semantic search for highlights by keyword, topic, or source, with lightning-fast, polished results.
Article Curations:
Support NIP-51 kind 30004 for article curations: Collections with a title, description, and image. Users can easily create new curations or add articles/highlights to existing ones via a streamlined, pixel-perfect interface (e.g., drag-and-drop or one-tap addition from feeds).
Displayed prominently in profiles and discoverable in feeds, with beautiful cover images and descriptive previews to wow curators and viewers alike.
Value Flows:
Integrated Lightning wallet (non-custodial, e.g., via Nostr Wallet Connect), with secure, visually appealing balance displays.
Zaps on highlights auto-split: e.g., 50% to author, 30% to highlighter, 20% to curator.
Premium Features: Optional in-app purchases for advanced tools (e.g., AI summarization), but core free, all gated with elegant upsell prompts.
Additional Tools:
Text-to-Speech: Read highlights aloud, with optional sat-streaming per minute, featuring smooth playback controls.
Import/Export: Seamless from Kindle, web clippers, or PDFs, with progress indicators that feel premium.
Offline Mode: Cache feeds/highlights for reading without internet, ensuring a flawless experience even offline.
4. User Flows
Onboarding:
Download and launch: Quick Nostr key generation (or import), guided by polished animations and tooltips.
Profile setup: Username, bio, interests (topics for feed personalization). Leverage follow packs (NIP-51, kind 39089) here—suggest importing popular packs (e.g., "Top Philosophy Curators") with beautiful previews of names, titles, and images to accelerate discovery and wow new users.
Tutorial: Swipe through demo highlights; learn to create/zap. Add a quick customization step for home screen sections (e.g., prioritize #bookstr discussions), all in an extremely engaging, pixel-perfect sequence.
Daily Use (Discovery Mode):
Open app: Land on Home—vertical scroll through mixed sections, with seamless loading to maintain flow.
Navigate: Swipe vertically for main flow; horizontally within carousels, feeling effortless and delightful.
Engage: Tap cards to expand (e.g., full article or thread); zap, reply, or save, with instant feedback.
Dive Deeper: Tap card to view full source with swarm overlays, immersing users in a wowing interface.
Creation Flow:
Tap "+" button: Choose source (paste URL, upload file, or in-app browser), in a clean, intuitive selector.
Select text: Drag to highlight; add notes/context, with real-time previews.
Publish: Choose public/private; auto-tags via NIP-84.
Share: Broadcast to relays; notify followers, with satisfying success animations.
Curation Flow:
From any article/highlight: Tap "Add to Curation" to select or create a new NIP-51 kind 30004 collection.
Creation: Set title, description, and upload/select image in a polished editor that makes curation feel effortless and premium.
Management: Edit curations in profile, with drag-and-drop reordering for pixel-perfect organization.
Social Flow:
Profile View: See user's highlights, articles, article curations (NIP-51 kind 30004 with titles, descriptions, images), zaps earned, followers, and follow packs.
Search: Type "quantum physics highlights" → results as cards, beautifully laid out.
Zap: Lightning QR or in-app send; confirm with haptic feedback and visual flair.
Follow Packs: Import/share packs (NIP-51 kind 39089) via QR, links, or in-app search, displaying names, titles, and images in stunning cards.
Edge Cases: Handle no-internet (local highlights), plagiarism checks (via timestamps), and spam (user-reported filters), all with graceful, polished error handling.
5. Screens and UI Breakdown
Use SwiftUI for native iOS feel, chasing pixel perfection in every component. Navigation: Bottom tab bar (Home, Search, Create, Profile, Library), with icons that animate subtly on tap.

Home Screen:
Layout: Vertical scrolling container with modular sections, blending content types for a dynamic, functional feel. Sections alternate between full-width vertical cards and horizontal carousels to prevent monotony and encourage exploration, all with extremely polished edges and shadows.
Sections Mix (customizable order via drag-and-drop in settings):
Personalized Recap (Vertical Cards): Top section—3-5 tall cards showing "Old Articles We Liked" (resurfaced from user's history, e.g., "You zapped this philosophy quote last month—revisit?"). Each card: Thumbnail, snippet, zap count, rendered flawlessly.
Trending Quotes (Horizontal Carousel): Swipe left/right through 5-10 highlight cards (NIP-84 quotes). Elegant snap-to-center scrolling; each card glows orange on hover, wowing with fluidity.
Community Zaps (Vertical Feed Snippet): 4-6 stacked cards of "Articles Liked/Zapped by Others" (from follows/network). Show social proof: "Your friend @user zapped this article on quantum mechanics," in crisp typography.
#Bookstr Discussions (Horizontal Carousel): Cards for kind:1 notes tagged #bookstr—thread previews with first post, reply count. Modern threading visualization (e.g., branched lines for replies), pixel-perfect in design.
Serendipity Mix (Vertical Infinite Scroll): Bottom infinite loader blending all types—quotes, zapped articles, personal olds, and discussions—for endless discovery, loading seamlessly.
Interactions: Pull-to-refresh entire home; section headers with "See More" buttons linking to dedicated feeds. Haptic feedback on swipes; adaptive layout for iPhone sizes (e.g., more horizontal items on larger screens), all tuned to wow.
Modern Touches: Parallax backgrounds on scrolls; subtle animations (e.g., cards "pop" when zapped). Functional filters at top: Toggle sections on/off, sort by recency/popularity, in an extremely polished bar.
Search/Discover Screen:
Search bar with suggestions.
Grid or list of results; trending topics sidebar. Enhanced with hybrid elements—search results in vertical list, with horizontal "Related Topics" carousels (e.g., #bookstr threads), all visually stunning.
Create Highlight Screen:
Text editor with import button.
Toolbar: Highlight tool (orange selector), add comment, tag authors, with icons that respond beautifully to taps.
Preview pane showing NIP-84 event structure, updated in real-time for pixel perfection.
Profile Screen:
Header: Avatar, bio, zap balance, displayed with high-fidelity images.
Tabs: My Highlights, My Articles, Article Curations (NIP-51 kind 30004 with titles, descriptions, images as elegant cards), Zaps Earned, Follows/Followers, Follow Packs (NIP-51 kind 39089 with names, titles, images). "My Mix" tab showing user's contributed content across types (highlights, discussions, curations).
Edit mode for Nostr key management, with secure, polished forms.
Library Screen:
Personal bookmarks/highlights (offline-accessible).
Collections: User-created folders (e.g., "Reading List"). Vertical list of saved items, with horizontal carousels for collections (e.g., "Zapped Articles"), all organized impeccably.
Full Content Viewer:
Modal: Render article/book with swarm overlays, zooming smoothly.
Tools: Highlight in-place, text-to-speech play button. Side-scroll for related discussions (#bookstr threads linked to the source), with fluid carousels.
Settings Screen (accessible via Profile):
Wallet integration, theme toggle (light/dark), notification prefs, relay selection. Options: Customize home sections (reorder, hide), feed density (more vertical vs. horizontal), and Nostr filters (e.g., specific #bookstr sub-tags), all in a clean, wowing interface.
6. Technical Integration
Nostr Core: Use NIP-84 for all highlights (kind:9802 events). Relays for syncing; support multiple for redundancy. Fetch and blend multiple kinds—kind:9802 for highlights/quotes, kind:1 for #bookstr discussions (query relays with hashtag filters), kind 30004 for article curations, kind 39089 for follow packs. Use Nostr's event tags for likes/zaps (e.g., reaction events).
Bitcoin/Lightning: Integrate via libraries like Breez SDK for zaps and prisms, with secure, pixel-perfect wallet UIs.
Data Model: Highlights as JSON events; local storage with Core Data for offline.
Feed Logic: Client-side mixing—query relays in parallel for sections; cache for offline. Horizontal carousels use UICollectionView for smooth performance.
Security: Private keys never leave device; biometric auth for wallet.
Scalability: Lazy-loading feeds; semantic search via local indexing or relay queries.
Compliance: iOS App Store guidelines—clear value flows as "tips," no gambling connotations.
7. Monetization and Growth
Free Tier: Unlimited basic use; quotas on public broadcasts to prevent spam.
Premium Subscription (app-specific): $4.99/month for unlimited zaps, advanced analytics (e.g., highlight impact), ad-free (though no ads anyway).
Value Economy: App takes 5-10% cut on zaps for sustainability; rest to users. Leverage hybrid home for better retention (e.g., A/B test section mixes).
Growth Strategies: Viral sharing (e.g., "Share this highlight"), integrations with Nostr clients, partnerships with authors/publishers for exclusive content. Use follow packs in onboarding to boost initial engagement.
Metrics: DAU via feed opens, engagement (zaps per highlight), retention (weekly learn streaks).
8. Roadmap and Future Ideas
v1.0 Launch: Core feed, creation, zaps. Home with mixed feeds, full support for article curations and follow packs.
v1.1: Audio/video highlights, swarm overlays. AI-driven section personalization (e.g., auto-suggest #bookstr based on interests).
v2.0: AI integrations (e.g., summarize highlights, suggest related).
Long-Term: Web version, Android port, metaverse-like "knowledge spaces" for live discussions. Voice integration for reading discussions aloud; VR modes for immersive "knowledge walks" through feeds.
Innovations: Gamification (badges for top highlighters), collaborative editing, integration with AR for "highlighting" real-world books via camera—all built with an unwavering commitment to pixel perfection and wowing users.
This spec serves as the blueprint for building Highlighter—a sanctuary for the mind in a noisy world. It draws inspiration from open protocols to create a product that's not just useful, but transformative, with an The user wants to update the Highlighter iOS app product spec with new features:

Profiles should include the user's articles and article curations using NIP-51 kind 30004. Article curations have a title, description, and image for the collection. It should be easy for users to create/add to these curations.
Support for follow packs (NIP-51, kind 39089), which have a name, title, and image; these are named sets of profiles to share. Leverage these in the onboarding flow.
Update the spec to emphasize an extremely polished UI, pixel perfection, and wowing the user. Repeat this throughout the text.
The current date is July 24, 2025, but that might not be relevant here.

I need to provide a complete, clean product spec incorporating these changes, without references to previous versions.

Structure the response similarly to the last one, integrating the new elements.

Key sections:

Overview and Value Proposition: Add mentions of curations and follow packs.
Ethos, Feel, and Aesthetics: Emphasize polish here.
Core Features: Add sections for article curations and follow packs.
User Flows: Update onboarding to include follow packs.
Screens and UI Breakdown: Update Profile screen to include articles and curations; add creation flows.
Technical Integration: Mention NIP-51 kinds.
Throughout, weave in language about polished UI, pixel perfection, wowing the user.

No tools needed, as this is spec updating based on user input.

Finally, output the updated spec.# Highlighter iOS App Product Specification

1. Overview and Value Proposition
Highlighter is a premium iOS application for intellectual discovery and knowledge sharing, built on the Nostr protocol with NIP-84 (kind:9802) for highlights and NIP-51 for advanced curation and social features. It empowers users to become smarter in their downtime by curating a dynamic mix of insightful content, from highlights and quotes to community discussions, personalized recommendations, article curations, and shared follow packs. The app draws from decentralized sources, ensuring censorship resistance and user ownership, while integrating Bitcoin Lightning zaps for value flows. Every interaction is designed with pixel-perfect precision to wow users, delivering an extremely polished UI that feels luxurious and intuitive from the first tap.

Target Audience: Intellectuals, lifelong learners, researchers, writers, and professionals aged 18-45 who value depth over distraction. Think: Reddit's r/books users, Kindle enthusiasts, or Notion power-users seeking a social layer.
Unique Selling Points:
Decentralized and censorship-resistant via Nostr: No central authority controls content; users own their data and identities.
Hybrid home screen: A modern blend of vertical and horizontal scrolling for a functional mix of content types, rendered with flawless animations to captivate and wow.
Swarm intelligence: Public highlights overlay on original content, showing what the community finds valuable (e.g., "swarm highlights" visualizing popular passages) in a visually stunning, pixel-perfect interface.
Value-enabled: Seamless zaps (micro-payments in sats) for appreciating highlights, with automatic splits to authors, curators, and highlighters, accompanied by elegant haptic feedback and ripple effects that delight users.
Cross-media support: Highlights from text, audio (timestamps), video (frame references), and more.
Article Curations: Effortless creation and sharing of themed collections (NIP-51 kind:30004) with titles, descriptions, and images, making organization feel magical and polished.
Follow Packs: Shareable sets of profiles (NIP-51 kind:39089) with names, titles, and images, integrated into onboarding for instant community building in a seamless, wow-inducing flow.
Mission Statement: Highlighter is where smart people flock to learn, share, and grow. It turns passive consumption into active enlightenment, fostering a global swarm of knowledge where value flows to those who illuminate the best ideas—all presented in an extremely polished UI that pursues pixel perfection to consistently wow users.
Highlighter positions itself as the antithesis to short-form video apps:
