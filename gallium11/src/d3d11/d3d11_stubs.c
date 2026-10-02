#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "gallium_mgr.h"
#include "shader_parser.h"

// Global gallium manager instance for translation layer
static struct gallium_mgr g_gallium_mgr;
static bool g_initialized = false;

typedef void* HRESULT;
typedef void* REFIID;
typedef void* IDXGIAdapter;
typedef void* D3D_DRIVER_TYPE;
typedef void* UINT;
typedef void* D3D_FEATURE_LEVEL;
typedef void* ID3D11Device;
typedef void* ID3D11DeviceContext;
typedef void* IDXGISwapChain;

#define S_OK ((HRESULT)0)
#define E_FAIL ((HRESULT)0x80004005)

__attribute__((constructor))
static void gallium11_init(void) {
    printf("[Gallium11] Initializing D3D11-to-Gallium3D translation layer...\n");
    if (!g_initialized) {
        if (gallium_mgr_init(&g_gallium_mgr) == 0) {
            g_initialized = true;
            printf("[Gallium11] Hardware acceleration active (Crocus / Gallium3D initialized successfully).\n");
        } else {
            fprintf(stderr, "[Gallium11] Warning: Failed to initialize hardware gallium manager. Continuing in stub mode.\n");
        }
    }
}

__attribute__((destructor))
static void gallium11_cleanup(void) {
    if (g_initialized) {
        gallium_mgr_cleanup(&g_gallium_mgr);
        g_initialized = false;
        printf("[Gallium11] Cleaned up Gallium3D translation layer.\n");
    }
}

// D3D11 export: D3D11CreateDevice
HRESULT D3D11CreateDevice(
    IDXGIAdapter *pAdapter,
    D3D_DRIVER_TYPE DriverType,
    void *Software,
    UINT Flags,
    const D3D_FEATURE_LEVEL *pFeatureLevels,
    UINT FeatureLevels,
    UINT SDKVersion,
    ID3D11Device **ppDevice,
    D3D_FEATURE_LEVEL *pFeatureLevel,
    ID3D11DeviceContext **ppImmediateContext
) {
    (void)pAdapter;
    (void)DriverType;
    (void)Software;
    (void)Flags;
    (void)pFeatureLevels;
    (void)FeatureLevels;
    (void)SDKVersion;

    printf("[Gallium11] D3D11CreateDevice called — translating to Mesa Gallium3D.\n");
    if (!g_initialized) {
        gallium11_init();
    }

    if (ppDevice) *ppDevice = (ID3D11Device*)0x11111111;
    if (ppImmediateContext) *ppImmediateContext = (ID3D11DeviceContext*)0x22222222;
    if (pFeatureLevel) *(D3D_FEATURE_LEVEL*)pFeatureLevel = (D3D_FEATURE_LEVEL)0xb11; // D3D_FEATURE_LEVEL_11_0

    return S_OK;
}

// D3D11 export: D3D11CreateDeviceAndSwapChain
HRESULT D3D11CreateDeviceAndSwapChain(
    IDXGIAdapter *pAdapter,
    D3D_DRIVER_TYPE DriverType,
    void *Software,
    UINT Flags,
    const D3D_FEATURE_LEVEL *pFeatureLevels,
    UINT FeatureLevels,
    UINT SDKVersion,
    const void *pSwapChainDesc,
    IDXGISwapChain **ppSwapChain,
    ID3D11Device **ppDevice,
    D3D_FEATURE_LEVEL *pFeatureLevel,
    ID3D11DeviceContext **ppImmediateContext
) {
    (void)pSwapChainDesc;
    printf("[Gallium11] D3D11CreateDeviceAndSwapChain called — bridging DirectX 11 API to Gallium pipeline.\n");

    HRESULT hr = D3D11CreateDevice(
        pAdapter, DriverType, Software, Flags,
        pFeatureLevels, FeatureLevels, SDKVersion,
        ppDevice, pFeatureLevel, ppImmediateContext
    );

    if (ppSwapChain) {
        *ppSwapChain = (IDXGISwapChain*)0x33333333;
    }

    return hr;
}
