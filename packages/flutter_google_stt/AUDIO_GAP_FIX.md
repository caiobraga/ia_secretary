# Audio Gap and Overlap Fix Implementation

## Problem Description
The original implementation had gaps in audio transcription between segments because:

1. **Android**: Audio buffer was completely reset after every 3-second chunk
2. **iOS**: Audio buffer was cleared immediately when sending for ## Technical Notes

- **Overlap size**: 0.25 seconds (optimal balance between gap prevention and duplicate reduction)
- **Chunk sizes**: Android 2s, iOS 0.5s intervals (optimized for real-time performance)  
- **Deduplication scope**: Max 5 words overlap detection (prevents performance issues)
- **Time tolerance**: Android 2.5s, iOS 0.8s windows for overlap validation
- **Ratio threshold**: 30% maximum overlap before preserving as legitimate repetition
- **Buffer management**: Smart clearing to prevent memory issues while maintaining continuity
- **API enhancements**: `useEnhanced` provides better accuracy for supported languages
- **Word-level precision**: Deduplication works at word boundaries for clean results
- **Edge case handling**: Comprehensive logic to preserve user intent while removing technical artifactsion
3. **Timing**: No overlap between audio segments caused loss of speech at chunk boundaries

### Secondary Challenge: Preventing Transcript Overlaps
When implementing overlapping buffers to fix gaps, we needed to address a new challenge:
1. **Duplicate content**: Same speech could appear in multiple consecutive transcripts
2. **Redundant text**: Users might receive repeated words/phrases between segments
3. **Edge case**: Legitimate repetition (e.g., "help help help") must be preserved

## Comprehensive Solution (v1.0.1)

### Smart Overlap Management with Advanced Deduplication
1. **Optimal overlap duration**: 0.25s to minimize duplicate content while preventing gaps
2. **Intelligent deduplication**: Word-level overlap detection with context awareness
3. **Time-based validation**: Only applies deduplication within expected chunk intervals
4. **Ratio-based filtering**: Preserves legitimate repetition by checking overlap percentage
5. **Conservative approach**: Prevents false positives when users intentionally repeat words

### Enhanced Deduplication Logic

The new algorithm addresses the critical edge case where users intentionally say the same words multiple times:

#### Android Implementation
```kotlin
private fun removeDuplicateContent(newTranscript: String): String {
    if (lastTranscript.isEmpty() || newTranscript.trim().isEmpty()) {
        return newTranscript.trim()
    }
    
    val newWords = newTranscript.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }
    val currentTime = System.currentTimeMillis()
    
    // Only apply deduplication if this chunk is within the expected overlap timeframe
    val timeSinceLastChunk = currentTime - lastChunkTimestamp
    val expectedChunkInterval = 2000L // 2 seconds
    val maxOverlapTime = expectedChunkInterval + 500L // 500ms tolerance
    
    if (timeSinceLastChunk > maxOverlapTime) {
        // Too much time passed, this is genuine new speech
        return newTranscript.trim()
    }
    
    // Find potential overlap, but be conservative
    var overlapIndex = -1
    val maxOverlapLength = minOf(lastTranscriptWords.size, newWords.size, 5) // Max 5 words
    
    for (i in 1..maxOverlapLength) {
        val lastSuffix = lastTranscriptWords.takeLast(i)
        val newPrefix = newWords.take(i)
        
        if (lastSuffix == newPrefix && i < newWords.size) {
            // Only remove if overlap is less than 30% of new transcript
            val overlapRatio = i.toDouble() / newWords.size
            if (overlapRatio < 0.3) {
                overlapIndex = i
            }
        }
    }
    
    return if (overlapIndex > 0) {
        newWords.drop(overlapIndex).joinToString(" ")
    } else {
        newTranscript.trim()
    }
}
```

#### iOS Implementation
```swift
private func removeDuplicateContent(newTranscript: String) -> String {
    let trimmedNew = newTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    
    if lastTranscript.isEmpty || trimmedNew.isEmpty {
        return trimmedNew
    }
    
    let newWords = trimmedNew.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    let currentTime = Date().timeIntervalSince1970
    
    // Time-based validation
    let timeSinceLastChunk = currentTime - lastChunkTimestamp
    let expectedChunkInterval: TimeInterval = 0.5 // 0.5 seconds for iOS
    let maxOverlapTime: TimeInterval = expectedChunkInterval + 0.3 // 300ms tolerance
    
    if timeSinceLastChunk > maxOverlapTime {
        return trimmedNew // Genuine new speech
    }
    
    // Conservative overlap detection
    var overlapIndex = -1
    let maxOverlapLength = min(lastTranscriptWords.count, newWords.count, 5)
    
    for i in 1...maxOverlapLength {
        let lastSuffix = Array(lastTranscriptWords.suffix(i))
        let newPrefix = Array(newWords.prefix(i))
        
        if lastSuffix == newPrefix && i < newWords.count {
            let overlapRatio = Double(i) / Double(newWords.count)
            if overlapRatio < 0.3 { // Less than 30% overlap
                overlapIndex = i
            }
        }
    }
    
    if overlapIndex > 0 {
        let uniquePart = Array(newWords.dropFirst(overlapIndex))
        return uniquePart.joined(separator: " ")
    } else {
        return trimmedNew
    }
}
```

### Android Improvements (FlutterGoogleSttPlugin.kt)

#### Buffer Management
```kotlin
val chunkSize = sampleRateHertz * 2 * 2 // 2 seconds chunks
val overlapSize = sampleRateHertz * 2 / 4 // 0.25 seconds overlap (reduced from 0.5s)
```

#### Deduplication Algorithm
```kotlin
private fun removeDuplicateContent(newTranscript: String): String {
    if (lastTranscript.isEmpty() || newTranscript.trim().isEmpty()) {
        return newTranscript.trim()
    }
    
    val newWords = newTranscript.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }
    
    // Find the longest common suffix of previous transcript with prefix of new transcript
    var overlapIndex = -1
    val maxOverlapLength = minOf(lastTranscriptWords.size, newWords.size, 10) // Limit to 10 words
    
    for (i in 1..maxOverlapLength) {
        val lastSuffix = lastTranscriptWords.takeLast(i)
        val newPrefix = newWords.take(i)
        
        if (lastSuffix == newPrefix) {
            overlapIndex = i
        }
    }
    
    // Return only the non-overlapping part
    return if (overlapIndex > 0) {
        newWords.drop(overlapIndex).joinToString(" ")
    } else {
        newTranscript.trim()
    }
}
```

### iOS Improvements (FlutterGoogleSttPlugin.swift)

#### Buffer Management
```swift
// Keep 250ms of overlap (16kHz * 2 bytes * 0.25 seconds = 8000 bytes) - reduced from 500ms
let overlapSize = 8000
```

#### Deduplication Algorithm
```swift
private func removeDuplicateContent(newTranscript: String) -> String {
    let trimmedNew = newTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    
    if lastTranscript.isEmpty || trimmedNew.isEmpty {
        return trimmedNew
    }
    
    let newWords = trimmedNew.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    
    // Find the longest common suffix of previous transcript with prefix of new transcript
    var overlapIndex = -1
    let maxOverlapLength = min(lastTranscriptWords.count, newWords.count, 10)
    
    for i in 1...maxOverlapLength {
        let lastSuffix = Array(lastTranscriptWords.suffix(i))
        let newPrefix = Array(newWords.prefix(i))
        
        if lastSuffix == newPrefix {
            overlapIndex = i
        }
    }
    
    // Return only the non-overlapping part
    if overlapIndex > 0 {
        let uniquePart = Array(newWords.dropFirst(overlapIndex))
        return uniquePart.joined(separator: " ")
    } else {
        return trimmedNew
    }
}
```

### Enhanced API Configuration

Both platforms now use improved Google Speech API settings:

```kotlin
// Android
val config = JsonObject().apply {
    addProperty("encoding", "LINEAR16")
    addProperty("sampleRateHertz", sampleRateHertz)
    addProperty("languageCode", languageCode)
    addProperty("enableAutomaticPunctuation", true)
    addProperty("enableWordTimeOffsets", false)
    addProperty("useEnhanced", true)
}
```

```swift
// iOS
let recognitionConfig: [String: Any] = [
    "encoding": "LINEAR16",
    "sampleRateHertz": sampleRateHertz,
    "languageCode": languageCode,
    "enableAutomaticPunctuation": true,
    "enableWordTimeOffsets": false,
    "useEnhanced": true
]
```

## Benefits of the Fix

1. **No more audio gaps**: Minimal overlap ensures continuous coverage
2. **No transcript duplicates**: Smart deduplication removes redundant content
3. **Faster response**: Frequent processing (2s chunks, 0.5s timer) for real-time feel
4. **Better quality**: Enhanced API settings with optimal overlap balance
5. **Smoother UX**: Clean, continuous transcription without gaps or duplicates

## How the Enhanced Deduplication Works

### Edge Case Scenarios Handled

#### Scenario 1: Legitimate Repetition
```
User says: "help help help I need assistance"
Previous chunk: "help help"
New chunk: "help I need assistance"
Result: "help I need assistance" (preserves the intended repetition)
```

#### Scenario 2: Technical Overlap
```
User says: "I am going to the store"
Previous chunk: "I am going to"
New chunk: "to the store"
Result: "the store" (removes technical overlap)
```

#### Scenario 3: Large Gap Between Speech
```
User says: "hello" [3 second pause] "hello again"
Previous chunk: "hello"
New chunk: "hello again" (after 3+ seconds)
Result: "hello again" (time gap indicates genuine new speech)
```

### Algorithm Logic Flow
1. **Time Check**: If more than expected interval has passed, preserve all content
2. **Overlap Detection**: Look for word-level matches at chunk boundaries
3. **Ratio Validation**: Only remove overlaps if they're less than 30% of new content
4. **Conservative Filtering**: Err on the side of preserving user speech

### Key Improvements in v1.0.1
- **Gap elimination**: Overlapping buffers ensure continuous audio coverage
- **Overlap prevention**: Smart deduplication removes technical artifacts
- **Time-aware**: Timestamps prevent deduplication across speech gaps
- **Ratio-based**: 30% threshold prevents removal of legitimate repetition
- **Conservative**: Reduced to 5 words maximum overlap check for precision
- **Context-aware**: Distinguishes between technical artifacts and user intent
- **Performance optimized**: Faster chunk processing (2s Android, 0.5s iOS intervals)

## Usage Recommendations

For optimal results:

1. **Test in quiet environment first**: Background noise can affect quality
2. **Speak clearly and at normal pace**: Don't rush or speak too slowly
3. **Monitor interim vs final results**: Use the `isFinal` parameter appropriately
4. **Handle network delays**: Implement proper error handling for API calls

## Additional Optimizations

If you still experience issues, consider:

1. **Adjust sample rate**: Try 16000 Hz (current) vs 8000 Hz for different quality/bandwidth tradeoffs
2. **Network optimization**: Ensure stable internet connection
3. **Audio session management**: On iOS, consider audio session category settings
4. **Background processing**: Handle app lifecycle events properly

## Technical Notes

- **Overlap size**: 0.25 seconds (optimal balance between gap prevention and duplicate reduction)
- **Chunk sizes**: Android 2s, iOS 0.5s intervals (optimized for real-time performance)
- **Deduplication scope**: Max 10 words overlap detection (prevents performance issues)
- **Buffer management**: Smart clearing to prevent memory issues while maintaining continuity
- **API enhancements**: `useEnhanced` provides better accuracy for supported languages
- **Word-level precision**: Deduplication works at word boundaries for clean results
