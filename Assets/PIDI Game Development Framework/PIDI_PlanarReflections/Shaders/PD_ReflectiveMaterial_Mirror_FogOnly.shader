﻿//
// PD_ReflectiveMaterial_FogOnly.shader
// Programmed  by : Jorge Pinal Negrete.
// This code is part of the PIDI Framework made by Jorge Pinal Negrete. for Irreverent Software.
// Copyright(c) 2015-2017, Jorge Pinal Negrete.  All Rights Reserved. 
//


Shader "PIDI Shaders Collection/Planar Reflection/Mirror/Fog Only" {
	Properties {
		[Header(Basic Properties)]
		_Glossiness( "Smoothness (for overlay)", Range( 0, 1 ) ) = 0//The smoothness of the overlay
		_Metallic( "Metallic (for overlay )", Range( 0, 1 ) ) = 0//The metallic value of the overlay
		_OverlayTex( "Overlay Tex", 2D ) = "black" {} //The overlay texture is rendered on top of the reflection and everything else. Useful for stains for example.
		_BumpMap( "Normal map", 2D ) = "bump"{} //This normal map distorts the reflection and works as a default normalmap as well.
		
		[Space(12)]
		[Header(Reflection Properties)]
		_RefDistortion( "Reflection Distortion", Range( 0, 0.08 ) ) = 0.03 //The distortion strength applied to the mirror surface
		_NormalStrength( "Bump+Distortion/Just Distortion", Range(0,1) ) = 1 //With this slider, you can change between applying normalmaps to the full rendering or only as distortion for the reflections
		_ReflectionTint("Reflection Tint", Color) = (1,1,1,1) //The tint that will be applied to the reflection
		_ReflectionTex ("ReflectionTex", 2D) = "white" {} //The texture that holds our real time reflection
		_NormalDist( "Surface Distortion", Range(0,1)) = 0 //Surface derived distortion	
		
		[Space(12)]
		[Header(Fog Properties)]
		_FogColor( "Fog Color", Color ) = (1,1,1,1) //The color of the fog over the mirror
		_FogTex( "Fog Texture (R = Coverage, G=PatternA B=PatternB A=Alpha)", 2D ) = "black" {} //The texture that controls the fog, its density and how it appears over the mirror
		_FogLevel( "Fog Level", Range( 0, 0.95 ) ) = 0 //The fog level over this mirror.	
		
	}
	SubShader {
		Tags { "RenderType"="Opaque" }
		LOD 600
		
		CGPROGRAM
		#pragma surface surf Standard fullforwardshadows
		#pragma target 3.0

		sampler2D _MainTex;
		sampler2D _FogTex;
		sampler2D _OverlayTex;
		sampler2D _ReflectionTex;
		sampler2D _BumpMap;

		struct Input {
			float2 uv_MainTex;
			float2 uv_FogTex;
			float2 uv_OverlayTex;
			float2 uv_BumpMap;
			float4 screenPos;
			float3 viewDir;
		};

		fixed4 _ReflectionTint;
		fixed4 _Color;
		fixed4 _FogColor;
		half _Glossiness;
		half _Metallic;
		half _NormalDist;
		half _RefDistortion;
		half _FogLevel;
		half _NormalStrength;
		
		void surf (Input IN, inout SurfaceOutputStandard o) {
			o.Normal = float3(0,0,1);

			half dist = 2*sign(dot(o.Normal, IN.viewDir)-0.5)*(dot(o.Normal,IN.viewDir)-0.5)*_NormalDist; //Normal based distortion factor

			o.Normal = UnpackNormal( tex2D( _BumpMap, IN.uv_BumpMap ) ); //We calculate the normals by unpacking the normalmap
			float2 nOffset = o.Normal*_RefDistortion; //We get the distortion by multiplying the normals by the disortion factor
			
			half4 ovTex = tex2D( _OverlayTex, IN.uv_OverlayTex ); //We get the colors from our overlay texture
			half4 fog = tex2D( _FogTex, IN.uv_FogTex ); //And from our fog texture
			
			//The fog is then calculated as follows :
			//The red channel of the texture is powered by 4 and multiplied by 1-_Fog Level to make the fog appear on the
			//mirror's surface progressively, from the lowest red value to the highest. The green and blue channels are mixed
			//to form a pattern that modifies how the fog will look, giving it a more realistic look. Finally, the alpha channel
			//is multiplied by the previous result and by the _FogLevel again, to define which parts have fog and which don't.
			half fTrans = saturate( pow( fog.r, 4*(1-_FogLevel) )*((fog.g+fog.b))*fog.a*2*_FogLevel);
			
			//The albedo of the shader is the overlay texture multiplied by the overlay alpha plus the fog color multiplied by our fog value (fTrans)
			//multiplied by the inverse of the overlay alpha. This will make the fog visible where the overlay is invisible and invisible where the overlay is visible,
			//effectively rendering the overlay texture over the fog.
			o.Albedo = ovTex*ovTex.a+(_FogColor*fTrans*saturate(1-ovTex.a));
			
			//We calculate the screen coordinates for the reflection.
			float2 screenUV = IN.screenPos.xy / max(IN.screenPos.w,0.001);
			
			screenUV += dist;

			//VR Single pass fix version 1.0
			#if UNITY_SINGLE_PASS_STEREO 
				//If Unity is rendering the scene in a single pass stereoscopic rendering mode, we need to repeat the image horizontally. This is of course not 100% phisycally accurate
				//produces the desired effect in almost any situation (except those where the stereoscopic separation between the eyes is abnormally large)

				screenUV.x = screenUV.x*2-floor(screenUV.x*2);

				//TODO : Future versions of this tool will have full support for physically accurate single pass stereoscopic rendering by merging two virtual eyes into a single accurate reflection texture.
			#endif


			half4 c = half4(0.0h,0.0h,0.0h,0.0h);   
			float blurFactor = _FogLevel*0.004*fTrans*saturate(1-ovTex.a*3); //We calculate our blur factor and multiply it by our fog factor so the fog makes the reflection blurry
			
			
			//We lerp the normals from our normals with bump mapping applied to a default positive plane normal with no bump map applied, to make the transition between bumpmap/distortion only
			o.Normal = normalize( lerp( o.Normal, float3(0,0,1) , _NormalStrength ) ); 
			
			
			c = tex2D ( _ReflectionTex, screenUV+nOffset); //We project our reflection texture and apply its offset
			
			
			//The reflection is sent to the emission channel, multiplied by the reflection color and multiplied by the inverse of the overlay alpha
			//so that the reflection is only visible where there is no overlay, making the overlay effectively appear over it, and then it is also
			//multiplied by the inverse of the fog value so the fog draws over the reflection as well.
			o.Emission = c.rgb*_ReflectionTint*(1-ovTex.a)*(1-fTrans);
			o.Metallic = _Metallic*ovTex.a;//The metallic value multiplied by the overlay alpha to affect only the overlay
			o.Smoothness = _Glossiness*ovTex.a;//The smoothness value multiplied by the overlay alpha so it only affects the overlay
			o.Alpha = 1;
		}
		
		
		ENDCG
		
		
	

		
	} 
	FallBack "Diffuse"
}
