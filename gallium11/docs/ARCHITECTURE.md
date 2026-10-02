# Gallium Eleven Architecture

Gallium Eleven is a bare-metal C frontend for Mesa's Gallium3D infrastructure that translates DirectX 11 (Direct3D 11 / DXGI) commands and DXBC shaders directly into Mesa NIR, optimized specifically for older generation Intel hardware such as the **Intel HD 4600 (Haswell)** using the **Crocus** driver.

---

## 1. High-Level Architecture

```
+-------------------------------------------------------+
|                Windows Application (DX11)             |
+-------------------------------------------------------+
                           |
                           v
+-------------------------------------------------------+
|              Wine DXGI & D3D11 DLLs                   |
|         (dxgi.dll / d3d11.dll runtime wrappers)       |
+-------------------------------------------------------+
                           |
                           v (COM interfaces / native calls)
+-------------------------------------------------------+
|                  Gallium Eleven Core                  |
|  - DXGI Swapchain & Surface Management                |
|  - D3D11 Device / Context Translation Layer           |
+-------------------------------------------------------+
                           |
       +-------------------+-------------------+
       v                                       v
+------------------------------+     +--------------------------+
|      Shader Translation      |     |  Gallium3D State Tracker |
|  - DXBC Bytecode Parser      |     |  - pipe_screen           |
|  - Translation to Mesa NIR   |     |  - pipe_context          |
+------------------------------+     +--------------------------+
       |                                       |
       +-------------------+-------------------+
                           |
                           v
+-------------------------------------------------------+
|                    Mesa Gallium3D                     |
|                   (Crocus Driver)                     |
+-------------------------------------------------------+
                           |
                           v
+-------------------------------------------------------+
|                   Intel HD 4600 GPU                   |
+-------------------------------------------------------+
```

---

## 2. Wine Entry Flow (`dxgi.dll` / `d3d11.dll`)

Gallium Eleven exposes standard Microsoft COM interfaces (`IDXGISwapChain`, `ID3D11Device`, `ID3D11DeviceContext`, etc.) by implementing them as a drop-in replacement or shim over Wine's loader, intercepting D3D11 API calls.

1. **Initialization**: The application calls `D3D11CreateDeviceAndSwapChain`. Gallium Eleven initializes the underlying Mesa `pipe_screen` using the DRI/GBM loader or direct software/hardware renderers targeted at the Crocus driver.
2. **Resource Creation**: Textures, buffers, and shaders created via D3D11 methods are mapped directly to Gallium resources (`pipe_resource`).
3. **Rendering Loop**: Draw calls (`Draw`, `DrawIndexed`) trigger state validation, uniform updates, and command buffer submission through `pipe_context`.

---

## 3. Gallium Interface Integration (`pipe_screen` / `pipe_context`)

Gallium Eleven abstracts all graphics operations through Gallium3D:
- **`pipe_screen`**: Represents the physical GPU device (Intel HD 4600 / Crocus). Used for querying caps, creating textures (`pipe_resource`), and compiling shaders.
- **`pipe_context`**: Represents the rendering context. Handles state binding (blend, rasterizer, depth/stencil), constant buffers, vertex/index buffers, and draw execution (`pipe_context->draw_vbo`).

---

## 4. Shader Parser Pipeline (DXBC to Mesa NIR)

DirectX 11 shaders use the **DXBC** (DirectX Bytecode) container format, containing RDEF, ISGN, OSGN, and SHDR (bytecode chunks).

1. **DXBC Parsing**:
   - Locate chunks by FourCC headers.
   - Parse token stream (tokens consist of opcode, length, and modifiers).
2. **Intermediate Representation (IR) Translation**:
   - Map DXBC opcodes (e.g., `mov`, `add`, `mul`, `dp4`, `sample`) into Mesa NIR instructions (`nir_builder`).
3. **NIR Optimization Passes**:
   - Run standard Mesa NIR optimizations (dead code elimination, algebraic simplifications).
4. **Backend Compilation**:
   - Pass the resulting NIR shader to the Crocus driver backend for generation of Intel Gen7.5 execution assembly.

---

## 5. Target Use Case: Rotating Cube

To validate the architecture, the primary milestone is rendering a simple colored rotating cube using pure DirectX 11 APIs (vertex buffers, constant buffers for world-view-projection matrices, input layouts, and basic shaders) running under Wine on Linux without any OpenGL or Vulkan translation layers in between.
