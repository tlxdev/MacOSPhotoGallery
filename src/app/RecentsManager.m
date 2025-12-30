/**
 * RecentsManager.m
 * Manages recently opened folders with NSUserDefaults persistence
 * Uses immutable patterns for thread safety
 */

#import "RecentsManager.h"

NSNotificationName const RecentsDidChangeNotification = @"RecentsDidChangeNotification";

static NSString * const kRecentsKey = @"RecentFolders";
static const NSUInteger kDefaultMaxRecents = 10;

@interface RecentsManager ()

@property (nonatomic, copy) NSArray<NSString *> *recentFoldersStorage;
@property (nonatomic, strong) dispatch_queue_t syncQueue;

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
        _syncQueue = dispatch_queue_create("com.photoviewer.recents", DISPATCH_QUEUE_SERIAL);
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
        
        self.recentFoldersStorage = [validPaths copy];
    } else {
        self.recentFoldersStorage = @[];
    }
}

- (void)saveRecents {
    [[NSUserDefaults standardUserDefaults] setObject:self.recentFoldersStorage
                                              forKey:kRecentsKey];
}

- (void)notifyChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:RecentsDidChangeNotification
                                                            object:self];
    });
}

#pragma mark - Properties

- (NSArray<NSString *> *)recentFolders {
    __block NSArray *result;
    dispatch_sync(self.syncQueue, ^{
        result = self.recentFoldersStorage;
    });
    return result;
}

#pragma mark - Public Methods

- (void)addRecentFolder:(NSString *)path {
    if (!path || path.length == 0) {
        return;
    }
    
    /* Normalize path */
    NSString *normalizedPath = path.stringByStandardizingPath;
    
    dispatch_async(self.syncQueue, ^{
        /* Create new array without the path (if it exists) */
        NSMutableArray *newRecents = [NSMutableArray array];
        [newRecents addObject:normalizedPath];
        
        for (NSString *existing in self.recentFoldersStorage) {
            if (![existing isEqualToString:normalizedPath]) {
                [newRecents addObject:existing];
            }
            
            /* Stop if we've reached max */
            if (newRecents.count >= self.maxRecents) {
                break;
            }
        }
        
        /* Replace with immutable copy */
        self.recentFoldersStorage = [newRecents copy];
        
        [self saveRecents];
        [self notifyChange];
    });
}

- (void)removeRecentFolder:(NSString *)path {
    if (!path) {
        return;
    }
    
    NSString *normalizedPath = path.stringByStandardizingPath;
    
    dispatch_async(self.syncQueue, ^{
        /* Create new array without the path */
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSString *item, NSDictionary * __unused bindings) {
            return ![item isEqualToString:normalizedPath];
        }];
        
        self.recentFoldersStorage = [self.recentFoldersStorage filteredArrayUsingPredicate:predicate];
        
        [self saveRecents];
        [self notifyChange];
    });
}

- (void)clearRecents {
    dispatch_async(self.syncQueue, ^{
        self.recentFoldersStorage = @[];
        [self saveRecents];
        [self notifyChange];
    });
}

- (NSString *)displayNameForPath:(NSString *)path {
    if (!path) {
        return @"";
    }
    return path.lastPathComponent;
}

@end
