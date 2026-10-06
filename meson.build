project('singularity-atelier', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-atelier"', language: 'c')
add_project_arguments('-w', language: 'c')
subdir('po')

cc         = meson.get_compiler('c')
gee_dep    = dependency('gee-0.8')
gio_dep    = dependency('gio-2.0')
json_dep   = dependency('json-glib-1.0')
xml_dep    = dependency('libxml-2.0')
zlib_dep   = dependency('zlib')
cairo_dep  = dependency('cairo')
pango_dep  = dependency('pangocairo')
pixbuf_dep = dependency('gdk-pixbuf-2.0')
gtk_dep    = dependency('gtk4')
lcms_dep   = dependency('lcms2', required: false)
math_dep   = cc.find_library('m')
gst_dep    = dependency('gstreamer-1.0')
peas_dep   = dependency('libpeas-2')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

plugin_api = shared_library('atelier-plugin',
  files('src/plugin/plugin_api.vala'),
  dependencies: [gio_dep],
  vala_header: 'atelier-plugin.h',
  vala_vapi: 'atelier-plugin.vapi',
  install: true,
  install_dir: [get_option('libdir'), true, true],
)
plugin_api_dep = declare_dependency(link_with: plugin_api, include_directories: include_directories('.'))

core_deps = [gee_dep, gio_dep, json_dep, xml_dep, zlib_dep, cairo_dep, pango_dep, pixbuf_dep, gtk_dep, math_dep, gst_dep, peas_dep, plugin_api_dep, libsingularity_dep]
core_args = ['--pkg', 'zlib']
if lcms_dep.found()
  core_deps += [lcms_dep]
  core_args += ['--vapidir', meson.current_source_dir() / 'vapi', '--pkg', 'lcms2', '-D', 'HAVE_LCMS']
endif

model = files(
  'src/model/expr.vala',
  'src/model/measurements.vala',
  'src/model/pattern.vala',
  'src/model/grading.vala',
  'src/model/darts.vala',
  'src/model/seams.vala',
  'src/model/leather.vala',
  'src/model/sketch.vala',
  'src/model/guides.vala',
  'src/model/flats.vala',
  'src/model/techpack.vala',
  'src/model/marker.vala',
  'src/model/samples.vala',
  'src/model/palettes.vala',
  'src/model/automotive.vala',
  'src/model/fill.vala',
  'src/model/digitize.vala',
  'src/model/project.vala',
)

sim = files(
  'src/sim/vec.vala',
  'src/sim/mesh.vala',
  'src/sim/avatar.vala',
  'src/sim/fabric.vala',
  'src/sim/cloth.vala',
  'src/sim/cloth_parallel.vala',
  'src/sim/subdiv.vala',
  'src/sim/raster3d.vala',
  'src/sim/nurbs.vala',
  'src/sim/product_editor.vala',
)

io = files(
  'src/io/zip.vala',
  'src/io/native.vala',
  'src/io/dxf.vala',
  'src/io/aama.vala',
  'src/io/seamly.vala',
  'src/io/hpgl.vala',
  'src/io/svg.vala',
  'src/io/ora.vala',
  'src/io/tables.vala',
  'src/io/odt.vala',
  'src/io/gltf.vala',
  'src/io/step.vala',
  'src/io/fbx.vala',
  'src/io/obj.vala',
  'src/io/psd.vala',
  'src/io/plugins.vala',
)

render = files(
  'src/render/sketch_renderer.vala',
  'src/render/pattern_renderer.vala',
  'src/render/flat_renderer.vala',
  'src/render/techpack_layout.vala',
  'src/render/pattern_print.vala',
  'src/render/export.vala',
  'src/render/timelapse.vala',
)

core = model + sim + io + render

gnome = import('gnome')
resources = gnome.compile_resources(
  'singularity-atelier-resources',
  'resources/dev.sinty.atelier.gresource.xml',
  source_dir: meson.current_source_dir() / 'data' / 'icons',
)

ui = files(
  'src/ui/app.vala',
  'src/ui/window.vala',
  'src/ui/view.vala',
  'src/ui/sketch_canvas.vala',
  'src/ui/sketch_panel.vala',
  'src/ui/pattern_canvas.vala',
  'src/ui/pattern_panel.vala',
  'src/ui/measurements_view.vala',
  'src/ui/flats_canvas.vala',
  'src/ui/flats_panel.vala',
  'src/ui/techpack_view.vala',
  'src/ui/view3d.vala',
  'src/ui/garment_panel.vala',
  'src/ui/product_panel.vala',
  'src/ui/library_panel.vala',
  'src/ui/dialogs.vala',
  'src/ui/patterns.vala',
  'src/ui/pattern_ribbon.vala',
  'src/ui/digitize_dialog.vala',
  'src/ui/print_sources.vala',
  'src/ui/cloud_actions.vala',
  'src/ui/test_script.vala',
)

executable('singularity-atelier',
  core + ui + [resources],
  dependencies: core_deps,
  vala_args: core_args,
  install_rpath: get_option('prefix') / get_option('libdir'),
  install: true
)

cut_list = shared_module('atelier-cut-list',
  files('plugin/cut_list.vala'),
  dependencies: [gio_dep, json_dep, peas_dep, plugin_api_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity-atelier' / 'plugins' / 'cut-list',
)
configure_file(input: 'plugin/cut-list.plugin', output: 'cut-list.plugin', copy: true)
install_data('plugin/cut-list.plugin',
  install_dir: get_option('libdir') / 'singularity-atelier' / 'plugins' / 'cut-list'
)

test_env = ['SINGULARITY_ATELIER_PLUGIN_PATH=' + meson.current_build_dir(), 'TMPDIR=' + meson.current_build_dir(), 'ATELIER_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures', 'LC_ALL=C.UTF-8']

foreach t : ['model', 'grading', 'sketch', 'dxf', 'seamly', 'formats', 'techpack', 'sim', 'mesh-io', 'plugin', 'product']
  exe = executable('atelier-' + t + '-test',
    core + files('tests/harness.vala', 'tests/' + t.underscorify() + '_test.vala'),
    dependencies: core_deps,
    vala_args: core_args,
  )
  test(t, exe, env: test_env, timeout: 300, depends: [cut_list])
endforeach

install_data('data/dev.sinty.atelier.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/dev.sinty.atelier.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/dev.sinty.atelier.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)
install_data('data/dev.sinty.atelier.open.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)
install_data('data/dev.sinty.atelier.xml',
  install_dir: get_option('datadir') / 'mime' / 'packages'
)
install_data('data/dev.sinty.atelier.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo'
)
install_data('data/icons/dev.sinty.atelier.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
