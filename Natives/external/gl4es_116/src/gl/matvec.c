#include "matvec.h"

#include <string.h>
#include <math.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
#include <arm_neon.h>
#endif

float FASTMATH dot(const float *a, const float *b) {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

float FASTMATH dot4(const float *a, const float *b) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    float32x4_t va = vld1q_f32(a);
    float32x4_t vb = vld1q_f32(b);
    float32x4_t prod = vmulq_f32(va, vb);
#if defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    return vaddvq_f32(prod);
#else
    float32x2_t sum = vadd_f32(vget_low_f32(prod), vget_high_f32(prod));
    return vget_lane_f32(vpadd_f32(sum, sum), 0);
#endif
#else
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3];
#endif
}

void cross3(const float *a, const float *b, float* c) {
    // Local temporaries avoid corrupting calculations if c aliases a or b
    float c0 = a[1]*b[2] - a[2]*b[1];
    float c1 = a[2]*b[0] - a[0]*b[2];
    float c2 = a[0]*b[1] - a[1]*b[0];
    c[0] = c0;
    c[1] = c1;
    c[2] = c2;
}

void matrix_vector(const float *a, const float *b, float *c) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    float32x4x4_t mat = vld4q_f32(a);
    float32x4_t res = vmulq_n_f32(mat.val[0], b[0]);
    res = vmlaq_n_f32(res, mat.val[1], b[1]);
    res = vmlaq_n_f32(res, mat.val[2], b[2]);
    res = vmlaq_n_f32(res, mat.val[3], b[3]);
    vst1q_f32(c, res);
#else
    const float b0 = b[0], b1 = b[1], b2 = b[2], b3 = b[3];
    c[0] = a[0] * b0 + a[1] * b1 + a[2] * b2 + a[3] * b3;
    c[1] = a[4] * b0 + a[5] * b1 + a[6] * b2 + a[7] * b3;
    c[2] = a[8] * b0 + a[9] * b1 + a[10] * b2 + a[11] * b3;
    c[3] = a[12] * b0 + a[13] * b1 + a[14] * b2 + a[15] * b3;
#endif
}

void vector_matrix(const float *a, const float *b, float *c) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    float32x4_t row0 = vld1q_f32(b);
    float32x4_t row1 = vld1q_f32(b + 4);
    float32x4_t row2 = vld1q_f32(b + 8);
    float32x4_t row3 = vld1q_f32(b + 12);
    float32x4_t res = vmulq_n_f32(row0, a[0]);
    res = vmlaq_n_f32(res, row1, a[1]);
    res = vmlaq_n_f32(res, row2, a[2]);
    res = vmlaq_n_f32(res, row3, a[3]);
    vst1q_f32(c, res);
#else
    const float a0=a[0], a1=a[1], a2=a[2], a3=a[3];
    c[0] = a0 * b[0] + a1 * b[4] + a2 * b[8] + a3 * b[12];
    c[1] = a0 * b[1] + a1 * b[5] + a2 * b[9] + a3 * b[13];
    c[2] = a0 * b[2] + a1 * b[6] + a2 * b[10] + a3 * b[14];
    c[3] = a0 * b[3] + a1 * b[7] + a2 * b[11] + a3 * b[15];
#endif
}

void vector3_matrix(const float *a, const float *b, float *c) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    float32x4_t row0 = vld1q_f32(b);
    float32x4_t row1 = vld1q_f32(b + 4);
    float32x4_t row2 = vld1q_f32(b + 8);
    float32x4_t row3 = vld1q_f32(b + 12);
    float32x4_t res = vmlaq_n_f32(row3, row0, a[0]);
    res = vmlaq_n_f32(res, row1, a[1]);
    res = vmlaq_n_f32(res, row2, a[2]);
    vst1q_f32(c, res);
#else
    c[0] = a[0] * b[0] + a[1] * b[4] + a[2] * b[8] + b[12];
    c[1] = a[0] * b[1] + a[1] * b[5] + a[2] * b[9] + b[13];
    c[2] = a[0] * b[2] + a[1] * b[6] + a[2] * b[10] + b[14];
    c[3] = a[0] * b[3] + a[1] * b[7] + a[2] * b[11] + b[15];
#endif
}

void vector3_matrix4(const float *a, const float *b, float *c) {
    c[0] = a[0] * b[0] + a[1] * b[4] + a[2] * b[8];
    c[1] = a[0] * b[1] + a[1] * b[5] + a[2] * b[9];
    c[2] = a[0] * b[2] + a[1] * b[6] + a[2] * b[10];
}

void vector3_matrix3(const float *a, const float *b, float *c) {
    c[0] = a[0] * b[0] + a[1] * b[3] + a[2] * b[6];
    c[1] = a[0] * b[1] + a[1] * b[4] + a[2] * b[7];
    c[2] = a[0] * b[2] + a[1] * b[5] + a[2] * b[8];
}

void vector_normalize(float *a) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    float dot_val = a[0]*a[0] + a[1]*a[1] + a[2]*a[2];
    if (dot_val > 0.0f) {
        float32x2_t v_dot = vdup_n_f32(dot_val);
        float32x2_t v_rsqrt = vrsqrte_f32(v_dot);
        v_rsqrt = vmul_f32(v_rsqrt, vrsqrts_f32(vmul_f32(v_dot, v_rsqrt), v_rsqrt));
        v_rsqrt = vmul_f32(v_rsqrt, vrsqrts_f32(vmul_f32(v_dot, v_rsqrt), v_rsqrt));
        float det = vget_lane_f32(v_rsqrt, 0);
        a[0] *= det;
        a[1] *= det;
        a[2] *= det;
    }
#else
    float det=1.0f/sqrtf(a[0]*a[0]+a[1]*a[1]+a[2]*a[2]);
    a[0]*=det;
    a[1]*=det;
    a[2]*=det;
#endif
}

void vector4_normalize(float *a) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    float dot_val = a[0]*a[0] + a[1]*a[1] + a[2]*a[2];
    if (dot_val > 0.0f) {
        float32x2_t v_dot = vdup_n_f32(dot_val);
        float32x2_t v_rsqrt = vrsqrte_f32(v_dot);
        v_rsqrt = vmul_f32(v_rsqrt, vrsqrts_f32(vmul_f32(v_dot, v_rsqrt), v_rsqrt));
        v_rsqrt = vmul_f32(v_rsqrt, vrsqrts_f32(vmul_f32(v_dot, v_rsqrt), v_rsqrt));
        float det = vget_lane_f32(v_rsqrt, 0);
        a[0] *= det;
        a[1] *= det;
        a[2] *= det;
    }
#else
    float det=1.0f/sqrtf(a[0]*a[0]+a[1]*a[1]+a[2]*a[2]);
    a[0]*=det;
    a[1]*=det;
    a[2]*=det;
    // a[3] is ignored and left as 0.0f
#endif
}

void FASTMATH matrix_transpose(const float *a, float *b) {
    // column major -> row major
    // a(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15) -> b(0,4,8,12,1,5,9,13,2,6,10,14,3,7,11,15)
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    float32x4x4_t mat = vld4q_f32(a);
    vst1q_f32(b,      mat.val[0]);
    vst1q_f32(b + 4,  mat.val[1]);
    vst1q_f32(b + 8,  mat.val[2]);
    vst1q_f32(b + 12, mat.val[3]);
#else
    for (int i=0; i<4; i++)
        for (int j=0; j<4; j++)
            b[i*4+j]=a[i+j*4];
#endif
}

void matrix_inverse(const float *m, float *r) {

    r[0] = m[5]*m[10]*m[15] - m[5]*m[14]*m[11] - m[6]*m[9]*m[15] + m[6]*m[13]*m[11] + m[7]*m[9]*m[14] - m[7]*m[13]*m[10];
    r[1] = -m[1]*m[10]*m[15] + m[1]*m[14]*m[11] + m[2]*m[9]*m[15] - m[2]*m[13]*m[11] - m[3]*m[9]*m[14] + m[3]*m[13]*m[10];
    r[2] = m[1]*m[6]*m[15] - m[1]*m[14]*m[7] - m[2]*m[5]*m[15] + m[2]*m[13]*m[7] + m[3]*m[5]*m[14] - m[3]*m[13]*m[6];
    r[3] = -m[1]*m[6]*m[11] + m[1]*m[10]*m[7] + m[2]*m[5]*m[11] - m[2]*m[9]*m[7] - m[3]*m[5]*m[10] + m[3]*m[9]*m[6];

    r[4] = -m[4]*m[10]*m[15] + m[4]*m[14]*m[11] + m[6]*m[8]*m[15] - m[6]*m[12]*m[11] - m[7]*m[8]*m[14] + m[7]*m[12]*m[10];
    r[5] = m[0]*m[10]*m[15] - m[0]*m[14]*m[11] - m[2]*m[8]*m[15] + m[2]*m[12]*m[11] + m[3]*m[8]*m[14] - m[3]*m[12]*m[10];
    r[6] = -m[0]*m[6]*m[15] + m[0]*m[14]*m[7] + m[2]*m[4]*m[15] - m[2]*m[12]*m[7] - m[3]*m[4]*m[14] + m[3]*m[12]*m[6];
    r[7] = m[0]*m[6]*m[11] - m[0]*m[10]*m[7] - m[2]*m[4]*m[11] + m[2]*m[8]*m[7] + m[3]*m[4]*m[10] - m[3]*m[8]*m[6];

    r[8] = m[4]*m[9]*m[15] - m[4]*m[13]*m[11] - m[5]*m[8]*m[15] + m[5]*m[12]*m[11] + m[7]*m[8]*m[13] - m[7]*m[12]*m[9];
    r[9] = -m[0]*m[9]*m[15] + m[0]*m[13]*m[11] + m[1]*m[8]*m[15] - m[1]*m[12]*m[11] - m[3]*m[8]*m[13] + m[3]*m[12]*m[9];
    r[10] = m[0]*m[5]*m[15] - m[0]*m[13]*m[7] - m[1]*m[4]*m[15] + m[1]*m[12]*m[7] + m[3]*m[4]*m[13] - m[3]*m[12]*m[5];
    r[11] = -m[0]*m[5]*m[11] + m[0]*m[9]*m[7] + m[1]*m[4]*m[11] - m[1]*m[8]*m[7] - m[3]*m[4]*m[9] + m[3]*m[8]*m[5];

    r[12] = -m[4]*m[9]*m[14] + m[4]*m[13]*m[10] + m[5]*m[8]*m[14] - m[5]*m[12]*m[10] - m[6]*m[8]*m[13] + m[6]*m[12]*m[9];
    r[13] = m[0]*m[9]*m[14] - m[0]*m[13]*m[10] - m[1]*m[8]*m[14] + m[1]*m[12]*m[10] + m[2]*m[8]*m[13] - m[2]*m[12]*m[9];
    r[14] = -m[0]*m[5]*m[14] + m[0]*m[13]*m[6] + m[1]*m[4]*m[14] - m[1]*m[12]*m[6] - m[2]*m[4]*m[13] + m[2]*m[12]*m[5];
    r[15] = m[0]*m[5]*m[10] - m[0]*m[9]*m[6] - m[1]*m[4]*m[10] + m[1]*m[8]*m[6] + m[2]*m[4]*m[9] - m[2]*m[8]*m[5];

    float det = 1.0f/(m[0]*r[0] + m[1]*r[4] + m[2]*r[8] + m[3]*r[12]);
    for (int i = 0; i < 16; i++) r[i] *= det;
}

void matrix_inverse3_transpose(const float *m, float *r) {
    
    r[0] = m[4+1]*m[8+2] - m[4+2]*m[8+1];
    r[1] = m[4+2]*m[8+0] - m[4+0]*m[8+2];
    r[2] = m[4+0]*m[8+1] - m[4+1]*m[8+0];

    r[3] = m[0+2]*m[8+1] - m[0+1]*m[8+2];
    r[4] = m[0+0]*m[8+2] - m[0+2]*m[8+0];
    r[5] = m[0+1]*m[8+0] - m[0+0]*m[8+1];

    r[6] = m[0+1]*m[4+2] - m[0+2]*m[4+1];
    r[7] = m[0+2]*m[4+0] - m[0+0]*m[4+2];
    r[8] = m[0+0]*m[4+1] - m[0+1]*m[4+0];

    float det = 1.0f/(m[0]*r[0] + m[4+0]*r[3] + m[8+0]*r[6]);
    for (int i = 0; i < 9; i++) r[i] *= det;
}
    
void matrix_mul(const float *a, const float *b, float *c) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    float32x4_t row_a0 = vld1q_f32(a);
    float32x4_t row_a1 = vld1q_f32(a + 4);
    float32x4_t row_a2 = vld1q_f32(a + 8);
    float32x4_t row_a3 = vld1q_f32(a + 12);

    float32x4_t res0 = vmlaq_n_f32(vmlaq_n_f32(vmlaq_n_f32(vmulq_n_f32(row_a0, b[0]), row_a1, b[1]), row_a2, b[2]), row_a3, b[3]);
    float32x4_t res1 = vmlaq_n_f32(vmlaq_n_f32(vmlaq_n_f32(vmulq_n_f32(row_a0, b[4]), row_a1, b[5]), row_a2, b[6]), row_a3, b[7]);
    float32x4_t res2 = vmlaq_n_f32(vmlaq_n_f32(vmlaq_n_f32(vmulq_n_f32(row_a0, b[8]), row_a1, b[9]), row_a2, b[10]), row_a3, b[11]);
    float32x4_t res3 = vmlaq_n_f32(vmlaq_n_f32(vmlaq_n_f32(vmulq_n_f32(row_a0, b[12]), row_a1, b[13]), row_a2, b[14]), row_a3, b[15]);

    vst1q_f32(c, res0);
    vst1q_f32(c + 4, res1);
    vst1q_f32(c + 8, res2);
    vst1q_f32(c + 12, res3);
#else
   float a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3],
        a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7],
        a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11],
        a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];

    float b0  = b[0], b1 = b[1], b2 = b[2], b3 = b[3];
    c[0] = b0*a00 + b1*a10 + b2*a20 + b3*a30;
    c[1] = b0*a01 + b1*a11 + b2*a21 + b3*a31;
    c[2] = b0*a02 + b1*a12 + b2*a22 + b3*a32;
    c[3] = b0*a03 + b1*a13 + b2*a23 + b3*a33;

    b0 = b[4]; b1 = b[5]; b2 = b[6]; b3 = b[7];
    c[4] = b0*a00 + b1*a10 + b2*a20 + b3*a30;
    c[5] = b0*a01 + b1*a11 + b2*a21 + b3*a31;
    c[6] = b0*a02 + b1*a12 + b2*a22 + b3*a32;
    c[7] = b0*a03 + b1*a13 + b2*a23 + b3*a33;

    b0 = b[8]; b1 = b[9]; b2 = b[10]; b3 = b[11];
    c[8] = b0*a00 + b1*a10 + b2*a20 + b3*a30;
    c[9] = b0*a01 + b1*a11 + b2*a21 + b3*a31;
    c[10] = b0*a02 + b1*a12 + b2*a22 + b3*a32;
    c[11] = b0*a03 + b1*a13 + b2*a23 + b3*a33;

    b0 = b[12]; b1 = b[13]; b2 = b[14]; b3 = b[15];
    c[12] = b0*a00 + b1*a10 + b2*a20 + b3*a30;
    c[13] = b0*a01 + b1*a11 + b2*a21 + b3*a31;
    c[14] = b0*a02 + b1*a12 + b2*a22 + b3*a32;
    c[15] = b0*a03 + b1*a13 + b2*a23 + b3*a33;
#endif
}

void vector4_mult(const float *a, const float *b, float *c) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    vst1q_f32(c, vmulq_f32(vld1q_f32(a), vld1q_f32(b)));
#else
    for (int i=0; i<4; i++)
        c[i] = a[i]*b[i];
#endif
}

void vector4_add(const float *a, const float *b, float *c) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    vst1q_f32(c, vaddq_f32(vld1q_f32(a), vld1q_f32(b)));
#else
    for (int i=0; i<4; i++)
        c[i] = a[i]+b[i];
#endif
}

void vector4_sub(const float *a, const float *b, float *c) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
    vst1q_f32(c, vsubq_f32(vld1q_f32(a), vld1q_f32(b)));
#else
    for (int i=0; i<4; i++)
        c[i] = a[i]-b[i];
#endif
}
    
void set_identity(float* mat) {
    memset(mat, 0, 16*sizeof(float));
    mat[0] = mat[1+4] = mat[2+8] = mat[3+12] = 1.0f;
}

int is_identity(const float* mat) {
    static float i1[16];
    static int set=0;
    if(!set) {set_identity(i1); set=1;}
    return memcmp(mat, i1, 16*sizeof(float))==0?1:0;
}
