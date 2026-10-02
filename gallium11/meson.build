project('gallium-eleven', 'c',
  version : '0.1.0',
  default_options : ['c_std=gnu11', 'warning_level=2', 'buildtype=release', 'optimization=3'])

cc = meson.get_compiler('c')

# Dependencies
libdrm_dep = dependency('libdrm', required : false)
gbm_dep = dependency('gbm', required : false)
x11_dep = dependency('x11', required : false)
m_dep = cc.find_library('m', required : false)

inc = include_directories('include')

common_src = files(
  'src/gallium_mgr.c',
  'src/parser/dxbc_parser.c',
  'src/parser/obj_parser.c',
  'src/shader_parser.c',
  'src/pipe_loader_stub.c'
)

d3d11_lib = shared_library('d3d11',
  [common_src, 'src/d3d11/d3d11_stubs.c'],
  include_directories : inc,
  dependencies : [libdrm_dep, gbm_dep],
  install : true
)

dxgi_lib = shared_library('dxgi',
  [common_src, 'src/dxgi/dxgi_stubs.c'],
  include_directories : inc,
  dependencies : [libdrm_dep, gbm_dep],
  install : true
)

# Executable for test
executable('cube_test',
  ['src/main.c', common_src],
  include_directories : inc,
  dependencies : [libdrm_dep, gbm_dep],
  link_with : [d3d11_lib, dxgi_lib]
)

# Executable for vkcube-style rotating cube & Wavefront OBJ renderer
if x11_dep.found() and libdrm_dep.found() and gbm_dep.found()
  executable('cube_renderer',
    ['src/cube_renderer.c', common_src],
    include_directories : inc,
    dependencies : [libdrm_dep, gbm_dep, x11_dep, m_dep],
    link_with : [d3d11_lib, dxgi_lib]
  )
endif
