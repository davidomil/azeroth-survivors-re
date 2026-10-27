use naga::back::wgsl::{write_string, WriterFlags};
use naga::front::wgsl::parse_str;
use naga::valid::{Capabilities, ValidationFlags, Validator};

#[test]
fn model_point_lights_emit_safari_parseable_literals() {
    check_point_lights("model", include_str!("../src/shaders/wow_model.wgsl"));
}

#[test]
fn terrain_point_lights_emit_safari_parseable_literals() {
    check_point_lights("terrain", include_str!("../src/shaders/terrain.wgsl"));
}

#[test]
fn static_world_point_lights_emit_safari_parseable_literals() {
    check_point_lights(
        "static world",
        include_str!("../../benilla-world/src/shaders/static_gx.wgsl"),
    );
}

fn check_point_lights(name: &str, shader: &str) {
    let start = shader
        .find("fn point_light_sum(")
        .expect("point-light function");
    let function = &shader[start..];
    let end = function.find("\n}").expect("point-light function end") + 2;
    let source = format!(
        "struct WowLight {{
            point_count: vec4<f32>,
            points: array<vec4<f32>, 512>,
        }};
        @group(0) @binding(0) var<storage, read> wow_light: WowLight;
        const TERRAIN_REACH: f32 = 33.570166;
        {}",
        &function[..end],
    );
    let module = parse_str(&source)
        .unwrap_or_else(|error| panic!("{name}: {}", error.emit_to_string(&source)));
    let info = Validator::new(ValidationFlags::all(), Capabilities::all())
        .validate(&module)
        .unwrap_or_else(|error| panic!("{name}: {error}"));
    let emitted = write_string(&module, &info, WriterFlags::empty()).expect("emit browser WGSL");

    // WebKit bug 314588 parsed whole-number f/h literals through i64 before checking the suffix.
    // Inspect Naga's output: it expands the source's scientific notation to this decimal form.
    let rejected: Vec<_> = emitted
        .split(|c: char| !c.is_ascii_alphanumeric() && c != '.' && c != '_')
        .filter_map(|token| token.strip_suffix('f').or_else(|| token.strip_suffix('h')))
        .filter(|digits| !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()))
        .filter(|digits| digits.parse::<i64>().is_err())
        .collect();
    assert!(
        rejected.is_empty(),
        "{name} emits float literals rejected by Safari's i64 lexer: {rejected:?}"
    );
}
