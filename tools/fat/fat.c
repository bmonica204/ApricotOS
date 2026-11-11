#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define FAT32_BAD_CLUSTER 0x0FFFFFF7
#define FAT32_EOC_MIN 0x0FFFFFF8

typedef struct{
    uint8_t  BootJumpInstruction[3];
    uint8_t  OemIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t  SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t  FatCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t  MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

    // specifically for FAT32
    uint32_t SectorsPerFat32;
    uint16_t Flags;
    uint16_t FatVersion;
    uint32_t RootCluster;
    uint16_t FsInfoSector;
    uint16_t BackupBootSector;
    uint8_t  Reserved[12];

    uint8_t  DriveNumber;
    uint8_t  _Reserved;
    uint8_t  Signature;
    uint32_t VolumeId; // value doesn't matter
    uint8_t  VolumeLabel[11]; // 11 bytes, padded w spaces
    uint8_t  SystemId[8];
} __attribute__((packed)) BootSector; 

_Static_assert(sizeof(BootSector) == 90, "FAT32 boot sector header must be 90 bytes");

typedef struct {
    uint8_t  Name[11];
    uint8_t  Attributes;
    uint8_t  _Reserved;
    uint8_t  CreatedTimeTenths;
    uint16_t CreationTime;
    uint16_t CreationDate;
    uint16_t AccessedDate;
    uint16_t FirstClusterHigh;
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;
    uint32_t Size;
} __attribute__((packed)) DirectoryEntry;

BootSector g_BootSector;
uint8_t* g_Fat = NULL;
DirectoryEntry* g_RootDirectory = NULL;
uint32_t g_RootDirectoryEntries = 0;
uint32_t g_DataLba;

bool readBootSector(FILE* disk){
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut){
    bool ok = true;
    ok = ok && (fseek(disk, (long)lba * g_BootSector.BytesPerSector, SEEK_SET) == 0);
    ok = ok && (fread(bufferOut, g_BootSector.BytesPerSector, count, disk) == count);
    return ok;
}

bool readFat(FILE* disk){
    g_Fat = (uint8_t*) malloc(g_BootSector.SectorsPerFat32 * g_BootSector.BytesPerSector);
    return readSectors(disk, g_BootSector.ReservedSectors, g_BootSector.SectorsPerFat32, g_Fat);
}

uint32_t clusterToLba(uint32_t cluster){
    return g_DataLba + (cluster - 2) * g_BootSector.SectorsPerCluster;
}

uint32_t nextCluster(uint32_t cluster){
    return ((uint32_t*)g_Fat)[cluster] & 0x0FFFFFFF;
}

bool isValidDataCluster(uint32_t cluster){
    return cluster >= 2 && cluster < FAT32_BAD_CLUSTER;
}

bool readClusterChain(FILE* disk, uint32_t cluster, uint8_t* outputBuffer){
    bool ok = true;
    while (ok && isValidDataCluster(cluster)) {
        ok = readSectors(disk, clusterToLba(cluster), g_BootSector.SectorsPerCluster, outputBuffer);
        outputBuffer += g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;
        cluster = nextCluster(cluster);
    }
    return ok;
}

bool readRootDirectory(FILE* disk){
    g_DataLba = g_BootSector.ReservedSectors + g_BootSector.FatCount * g_BootSector.SectorsPerFat32;

    uint32_t clusters = 0;
    uint32_t cluster = g_BootSector.RootCluster;
    while (isValidDataCluster(cluster) && clusters < 0x100000) {
        clusters++;
        cluster = nextCluster(cluster);
    }
    if (clusters == 0)
        return false;

    uint32_t clusterBytes = g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;
    g_RootDirectoryEntries = clusters * clusterBytes / sizeof(DirectoryEntry);
    g_RootDirectory = (DirectoryEntry*) malloc(clusters * clusterBytes);
    return readClusterChain(disk, g_BootSector.RootCluster, (uint8_t*) g_RootDirectory);
}

void formatFileName(const char* name, char* dest) {
    memset(dest, ' ', 11);
    int i = 0;
    int j = 0;
    while (name[i] != '\0' && name[i] != '.' && i < 8) {
        dest[j++] = toupper(name[i++]);
    }
    if (name[i] == '.') {
        i++;
        j = 8;
        int extCount = 0;
        while (name[i] != '\0' && extCount < 3) {
            dest[j++] = toupper(name[i++]);
            extCount++;
        }
    }
}

DirectoryEntry* findFile(const char* name) {
    char formattedName[11];
    formatFileName(name, formattedName);

    for (uint32_t i = 0; i < g_RootDirectoryEntries; i++){
        uint8_t first = g_RootDirectory[i].Name[0];
        if (first == 0x00) break;
        if (first == 0xE5) continue;
        if (g_RootDirectory[i].Attributes & 0x08) continue;
        if (memcmp(formattedName, g_RootDirectory[i].Name, 11) == 0){
            return &g_RootDirectory[i];
        }
    }
    return NULL;
}

bool readFile(DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer){
    uint32_t cluster = ((uint32_t)fileEntry->FirstClusterHigh << 16) | fileEntry->FirstClusterLow;
    return readClusterChain(disk, cluster, outputBuffer);
}

int main(int argc, char** argv){
    if (argc < 3) {
        printf("Syntax: %s <disk image> <file name>\n", argv[0]);
        return -1;
    }

    FILE* disk = fopen(argv[1], "rb");
    if (!disk){
        fprintf(stderr, "Cannot open disk image %s!", argv[1]);
        return -1;
    }

    if (!readBootSector(disk)){
        fprintf(stderr, "Could not read boot sector!\n");
        return -2;
    }

    if (g_BootSector.SectorsPerFat == 0 && g_BootSector.SectorsPerFat32 == 0) {
        fprintf(stderr, "Not a FAT32 image!\n");
        return -2;
    }

    if(!readFat(disk)){
        fprintf(stderr, "Could not read FAT!\n");
        free(g_Fat);
        return -3;
    }

    if (!readRootDirectory(disk)) {
        fprintf(stderr, "Could not read root directory!\n");
        free(g_Fat);
        free(g_RootDirectory);
        return -4;
    }

    DirectoryEntry* fileEntry = findFile(argv[2]);
    if (!fileEntry) {
        fprintf(stderr, "Could not find file %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        return -5;
    }

    uint32_t clusterBytes = g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;
    uint8_t* buffer = (uint8_t*) malloc(fileEntry->Size + clusterBytes);
    if (!readFile(fileEntry, disk, buffer)) {
        fprintf(stderr, "Could not read file %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        free(buffer);
        return -5;
    }

    for (size_t i = 0; i < fileEntry->Size; i++){
        if (isprint(buffer[i])) fputc(buffer[i], stdout);
        else printf("<%02x>", buffer[i]);
    }
    printf("\n");

    free(buffer);
    free(g_Fat);
    free(g_RootDirectory);
    return 0;
}
