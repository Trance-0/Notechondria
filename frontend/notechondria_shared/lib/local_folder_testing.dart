/// Test doubles for the local folder module (design 8.2). Tests only:
/// production code never imports this library.
library local_folder_testing;

export 'src/local_folder/folder_fs_memory.dart'
    show MemoryFolderCrash, MemoryFolderFs;
export 'src/local_folder/folder_lock.dart' show MemoryFolderLocks;
export 'src/local_folder/memory_platform.dart'
    show
        MemoryFolderChangeChannel,
        MemoryFolderChangeHub,
        MemoryFolderPicker,
        MemoryFolderPlatform,
        MemoryHandleStore;
