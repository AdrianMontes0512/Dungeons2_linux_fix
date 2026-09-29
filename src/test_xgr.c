#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

typedef struct XAsyncBlock {
    void *queue;
    void *context;
    void (__stdcall *callback)(struct XAsyncBlock *);
    unsigned char internal[32];
} XAsyncBlock;

static int got;
static void __stdcall on_done(XAsyncBlock *b) { (void)b; got = 1; }
static HRESULT __stdcall do_work(XAsyncBlock *b) { (void)b; return 0; }

int main(void)
{
    HMODULE m;
    HRESULT (__stdcall *init)(uint64_t, uint64_t, uint32_t, const void *);
    HRESULT (__stdcall *query)(const GUID *, const GUID *, void **);
    void *thr = NULL;
    void **vt;
    GUID id = { 0x073b7dcb, 0x1fcf, 0x4030, { 0x94, 0xbe, 0xe3, 0xc9, 0xeb, 0x62, 0x34, 0x28 } };
    HRESULT hr;
    void *queue = NULL;
    XAsyncBlock block;
    int fails = 0;

    m = LoadLibraryA("xgameruntime.dll");
    if (!m) { printf("load %lu\n", GetLastError()); return 1; }
    init = (void *)GetProcAddress(m, "InitializeApiImplEx2");
    query = (void *)GetProcAddress(m, "QueryApiImpl");
    if (!init || !query) { printf("exports missing\n"); return 1; }
    hr = init(0x633600002712ull, 0x65f400001e9full, 0, NULL);
    printf("init %08lx\n", (unsigned long)hr);
    if (hr) fails++;
    hr = query(&id, &id, &thr);
    printf("query %08lx %p\n", (unsigned long)hr, thr);
    if (hr || !thr) return 1;
    vt = *(void ***)thr;

    memset(&block, 0, sizeof(block));
    block.callback = on_done;
    hr = ((HRESULT (__stdcall *)(void *, XAsyncBlock *, void *))vt[6])(thr, &block, do_work);
    printf("run %08lx\n", (unsigned long)hr);
    Sleep(300);
    hr = ((HRESULT (__stdcall *)(void *, XAsyncBlock *, unsigned char))vt[3])(thr, &block, 1);
    printf("status %08lx callback %d\n", (unsigned long)hr, got);
    if (hr || !got) fails++;

    got = 0;
    hr = ((HRESULT (__stdcall *)(void *, uint32_t, uint32_t, void **))vt[12])(thr, 0, 0, &queue);
    printf("manual queue %08lx %p\n", (unsigned long)hr, queue);
    memset(&block, 0, sizeof(block));
    block.queue = queue;
    block.callback = on_done;
    hr = ((HRESULT (__stdcall *)(void *, XAsyncBlock *, void *))vt[6])(thr, &block, do_work);
    ((unsigned char (__stdcall *)(void *, void *, uint32_t, uint32_t))vt[16])(thr, queue, 0, 100);
    ((unsigned char (__stdcall *)(void *, void *, uint32_t, uint32_t))vt[16])(thr, queue, 1, 100);
    hr = ((HRESULT (__stdcall *)(void *, XAsyncBlock *, unsigned char))vt[3])(thr, &block, 0);
    printf("manual status %08lx callback %d\n", (unsigned long)hr, got);
    if (hr || !got) fails++;
    printf(fails ? "FAIL\n" : "OK\n");
    return fails ? 1 : 0;
}
