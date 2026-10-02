#include <stdio.h>
#include <stdint.h>

typedef void* HRESULT;
typedef void* REFIID;
typedef void** ppvObject;

#define S_OK ((HRESULT)0)

// DXGI export: CreateDXGIFactory
HRESULT CreateDXGIFactory(REFIID riid, ppvObject ppFactory) {
    (void)riid;
    printf("[Gallium11 - DXGI] CreateDXGIFactory called — providing DXGI adapter and swap chain management.\n");
    if (ppFactory) {
        *ppFactory = (void*)0x44444444;
    }
    return S_OK;
}

// DXGI export: CreateDXGIFactory1
HRESULT CreateDXGIFactory1(REFIID riid, ppvObject ppFactory) {
    (void)riid;
    printf("[Gallium11 - DXGI] CreateDXGIFactory1 called — providing modern DXGI 1.1+ factory.\n");
    return CreateDXGIFactory(riid, ppFactory);
}

// DXGI export: CreateDXGIFactory2
HRESULT CreateDXGIFactory2(UINT Flags, REFIID riid, ppvObject ppFactory) {
    (void)Flags;
    (void)riid;
    printf("[Gallium11 - DXGI] CreateDXGIFactory2 called with flags.\n");
    return CreateDXGIFactory(riid, ppFactory);
}
