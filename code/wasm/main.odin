package wasm

import "core:fmt"
import gl "vendor:wasm/WebGL"

MainCanvasId := "canvas"

main :: proc() {
    gl.SetCurrentContextById(MainCanvasId)
    
    gl.ClearColor(0x18/255.0,0x18/255.0,0x18/255.0,1)
    gl.Clear(auto_cast gl.COLOR_BUFFER_BIT)
    
    vertex_shader_source := `#version 300 es
precision mediump float;

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec4 a_color;

out vec4 f_color;

void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
    f_color = a_color;
}
`

    fragment_shader_source := `#version 300 es
precision mediump float;

in vec4 f_color;
out vec4 out_color;

void main() {
    out_color = f_color;
}
`
    
    program, ok := gl.CreateProgramFromStrings({vertex_shader_source}, {fragment_shader_source})
    assert(ok)
    
    v2 :: [2] f32
    v4 :: [4] f32
    
    vertices := [] v2 {
        {-0.5, -0.5},
        { 0.5, -0.5},
        { 0.0,  0.5},
    }
    
    
    colors := [] v4 {
        {1.0, 0.0, 0.0, 1.0},
        {0.0, 1.0, 0.0, 1.0},
        {0.0, 0.0, 1.0, 1.0},
    }
    
    vao := gl.CreateVertexArray()
    p_buffer := gl.CreateBuffer()
    c_buffer := gl.CreateBuffer()
    
    gl.UseProgram(program)
    
    gl.BindVertexArray(vao)
        
        gl.BindBuffer(gl.ARRAY_BUFFER, p_buffer)
        gl.BufferData(gl.ARRAY_BUFFER, len(vertices)*size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)
        
        gl.EnableVertexAttribArray(0)
        gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)
        
        gl.BindBuffer(gl.ARRAY_BUFFER, c_buffer)
        gl.BufferData(gl.ARRAY_BUFFER, len(colors)*size_of(colors[0]), raw_data(colors), gl.STATIC_DRAW)
        
        gl.EnableVertexAttribArray(1)
        gl.VertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0)
        
        gl.UseProgram(program)
        gl.BindVertexArray(vao)
        gl.DrawArrays(gl.TRIANGLES, 0, 3)
        
    gl.BindVertexArray(0)
        
    gl.UseProgram(0)
}