//
//  WDMViewController.m
//  SCGDemo
//
//  Created by yoshimura atsushi on 2014/03/13.
//  Copyright (c) 2014年 wow. All rights reserved.
//

#import "WDMViewController.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <GLKit/GLKit.h>

#include <vector>

#import "GShader.h"
#import "GMacros.h"
#import "USKCamera.h"

static double remap(double value, double inputMin, double inputMax, double outputMin, double outputMax)
{
    return (value - inputMin) * ((outputMax - outputMin) / (inputMax - inputMin)) + outputMin;
}

@implementation WDMViewController
{
    USKOpenGLView *_openglView;
    EAGLContext *_context;
    
    JSContext *_jsContext;
    
    std::vector<GLKVector3> m_linesVertices;
    GShader *_lineShader;
    USKCamera *_camera;
    
    NSDate *_begin;
    
    CGPoint _touch;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [EAGLContext setCurrentContext:_context];
    _openglView = [[USKOpenGLView alloc] initWithFrame:self.view.bounds context:_context];
    [self.view addSubview:_openglView];
    
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 60.0
                                             target:self
                                           selector:@selector(onUpdate:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    
    _jsContext = [[JSContext alloc] init];
    
    NSString *csgJSPath = [[NSBundle mainBundle] pathForResource:@"csg.js" ofType:@""];
    NSError *error;
    NSString *csgJS = [NSString stringWithContentsOfFile:csgJSPath encoding:NSUTF8StringEncoding error:&error];
    [_jsContext evaluateScript:csgJS];
    
    NSString *const kLineShaderVS = SHADER_STRING(
                                                  uniform mat4 u_transform;
                                                  attribute vec4 a_position;
                                                  void main()
                                                  {
                                                      gl_Position = u_transform * a_position;
                                                  }
                                                  );
    NSString *const kLineShaderFS = SHADER_STRING(
                                                  precision highp float;
                                                  uniform vec4 u_color;
                                                  void main()
                                                  {
                                                      gl_FragColor = u_color;
                                                  }
                                                  );
    _lineShader = [[GShader alloc] initWithVertexShader:kLineShaderVS fragmentShader:kLineShaderFS error:&error];
    
    _camera = [[USKCamera alloc] init];
    _camera.aspect = self.view.bounds.size.width / self.view.bounds.size.height;
    _begin = [NSDate date];
}
- (void)onUpdate:(NSTimer *)sender
{
    double elaped = [[NSDate date] timeIntervalSinceDate:_begin];
    
    glBindFramebuffer(GL_FRAMEBUFFER, _openglView.framebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _openglView.colorRenderbuffer);
    glViewport(0, 0, _openglView.glBufferWidth, _openglView.glBufferHeight);
    
    glClearColor(1.0f, 1.0f, 1.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    m_linesVertices.clear();
    
    int N = 20;
    for(int i = 0 ; i < N ; ++i)
    {
        float x = remap(i, 0, N - 1, -5, 5);
        GLKVector3 p0 = GLKVector3Make(x, 0, -5);
        GLKVector3 p1 = GLKVector3Make(x, 0, 5);
        m_linesVertices.push_back(p0); m_linesVertices.push_back(p1);
    }
    for(int i = 0 ; i < N ; ++i)
    {
        float z = remap(i, 0, N - 1, -5, 5);
        GLKVector3 p0 = GLKVector3Make(-5, 0, z);
        GLKVector3 p1 = GLKVector3Make(5, 0, z);
        m_linesVertices.push_back(p0); m_linesVertices.push_back(p1);
    }
    [_lineShader bind:^{
        [_lineShader setVector4:GLKVector4Make(0.7, 0.7, 0.7, 1) forUniformKey:@"u_color"];
        [_lineShader setMatrix4:GLKMatrix4Multiply([_camera proj], [_camera view]) forUniformKey:@"u_transform"];
        
        GLKVector3 *head = m_linesVertices.data();
        int a_position = [_lineShader attribLocationForKey:@"a_position"];
        glVertexAttribPointer(a_position, 3, GL_FLOAT, GL_FALSE, sizeof(GLKVector3), head);
        glEnableVertexAttribArray(a_position);
        
        glDrawArrays(GL_LINES, 0, (int)m_linesVertices.size());
        
        glDisableVertexAttribArray(a_position);
    }];

    m_linesVertices.clear();
    
    float sphere1X = remap(sinf(elaped * 0.5f), -1, 1, -0.8, 0.8);
    float sphere1Y = 0.0f;
    float sphere1Z = remap(cosf(elaped * 0.5f), -1, 1, -0.8, 0.8);
    NSString *js = [NSString stringWithFormat:@"var cube = CSG.cube();\nvar sphere1 = CSG.sphere({ radius: 1.0, center: [%f, %f, %f] });\nvar polygons = cube.subtract(sphere1).toPolygons();", sphere1X, sphere1Y, sphere1Z];
    [_jsContext evaluateScript:js];
    JSValue *polygons = _jsContext[@"polygons"];
    NSRange polygonsRange = [polygons toRange];
    if(polygonsRange.location == 0)
    {
        for(int i = 0 ; i < polygonsRange.length ; ++i)
        {
            JSValue *polygon = polygons[i];
            JSValue *vertices = polygon[@"vertices"];
            NSRange verticesRange = [vertices toRange];
            if(verticesRange.location != 0 || verticesRange.length < 3)
            {
                continue;
            }
            
            JSValue *v0 = vertices[0];
            JSValue *p0 = v0[@"pos"];
            GLKVector3 gp0 = GLKVector3Make([p0[@"x"] toDouble], [p0[@"y"] toDouble], [p0[@"z"] toDouble]);
            for(int j = 0 ; j < verticesRange.length - 2 ; ++j)
            {
                JSValue *v1 = vertices[j + 1];
                JSValue *v2 = vertices[j + 2];
                
                JSValue *p1 = v1[@"pos"];
                JSValue *p2 = v2[@"pos"];
        
                GLKVector3 gp1 = GLKVector3Make([p1[@"x"] toDouble], [p1[@"y"] toDouble], [p1[@"z"] toDouble]);
                GLKVector3 gp2 = GLKVector3Make([p2[@"x"] toDouble], [p2[@"y"] toDouble], [p2[@"z"] toDouble]);
                
                // ポリゴンを構築
                m_linesVertices.push_back(gp0); m_linesVertices.push_back(gp1);
                m_linesVertices.push_back(gp1); m_linesVertices.push_back(gp2);
                m_linesVertices.push_back(gp2); m_linesVertices.push_back(gp0);
            }
        }
    }
    
    float rot = remap(_touch.x, 0, self.view.bounds.size.width, 0, M_PI * 2.0);
    float h = remap(_touch.y, 0, self.view.bounds.size.height, 10.0, -10.0);
    
    _camera.position = GLKVector3Make(sinf(rot) * 10.0f, h, cosf(rot) * 10.0f);
    
    [_lineShader bind:^{
        [_lineShader setVector4:GLKVector4Make(0, 0, 0, 1) forUniformKey:@"u_color"];
        [_lineShader setMatrix4:GLKMatrix4Multiply([_camera proj], [_camera view]) forUniformKey:@"u_transform"];
        
        GLKVector3 *head = m_linesVertices.data();
        int a_position = [_lineShader attribLocationForKey:@"a_position"];
        glVertexAttribPointer(a_position, 3, GL_FLOAT, GL_FALSE, sizeof(GLKVector3), head);
        glEnableVertexAttribArray(a_position);
        
        glDrawArrays(GL_LINES, 0, (int)m_linesVertices.size());
        
        glDisableVertexAttribArray(a_position);
    }];

    [_context presentRenderbuffer:GL_RENDERBUFFER];
}
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    _touch = [touch locationInView:self.view];
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    _touch = [touch locationInView:self.view];
}
@end
