/**
 * RecentsManager.m
 * Manages recently opened folders with NSUserDefaults persistence
 */

#import "RecentsManager.h"

NSNotificationName const RecentsDidChangeNotification = @"RecentsDidChangeNotification";

static NSString * const kRecentsKey = @"RecentFolders";
static const NSUInteger kDefaultMaxRecents = 10;

@interface RecentsManager ()

@property (nonatomic, strong) NSMutableArray<NSString *> *mutableRecentFolders;

@end

@implementation RecentsManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static RecentsManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[RecentsManager alloc] init];
    });
    return manager;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxRecents = kDefaultMaxRecents;
        [self loadRecents];
    }
    return self;
}

#pragma mark - Persistence

- (void)loadRecents {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kRecentsKey];
    
    if (saved) {
        /* Filter out paths that no longer exist */
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *validPaths = [NSMutableArray array];
        
        for (NSString *path in saved) {
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
                [validPaths addObject:path];
            }
        }
        
        self.mutableRecentFolders = validPaths;
    } else {
        self.mutableRecentFolders = [NSMutableArray array];
    }
}

- (void)saveRecents {
    [[NSUserDefaults standardUserDefaults] setObject:[self.mutableRecentFolders copy] 
                                              forKey:kRecentsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)notifyChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:RecentsDidChangeNotification
                                                        object:self];
}

#pragma mark - Properties

- (NSArray<NSString *> *)recentFolders {
    return [self.mutableRecentFolders copy];
}

#pragma mark - Public Methods

- (void)addRecentFolder:(NSString *)path {
    if (!path || path.length == 0) {
        return;
    }
    
    /* Normalize path */
    NSString *normalizedPath = path.stringByStandardizingPath;
    
    /* Remove if already exists (will re-add at top) */
    [self.mutableRecentFolders removeObject:normalizedPath];
    
    /* Add to beginning */
    [self.mutableRecentFolders insertObject:normalizedPath atIndex:0];
    
    /* Trim to max size */
    while (self.mutableRecentFolders.count > self.maxRecents) {
        [self.mutableRecentFolders removeLastObject];
    }
    
    [self saveRecents];
    [self notifyChange];
}

- (void)removeRecentFolder:(NSString *)path {
    if (!path) {
        return;
    }
    
    NSString *normalizedPath = path.stringByStandardizingPath;
    [self.mutableRecentFolders removeObject:normalizedPath];
    
    [self saveRecents];
    [self notifyChange];
}

- (void)clearRecents {
    [self.mutableRecentFolders removeAllObjects];
    [self saveRecents];
    [self notifyChange];
}

- (NSString *)displayNameForPath:(NSString *)path {
    if (!path) {
        return @"";
    }
    return path.lastPathComponent;
}

@end

