/* bzflag
 * Copyright (c) 1993 - 2008 Tim Riker
 *
 * This package is free software;  you can redistribute it and/or
 * modify it under the terms of the license found in the file
 * named COPYING that should have accompanied this file.
 *
 * THIS PACKAGE IS PROVIDED ``AS IS'' AND WITHOUT ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
 */

#ifndef __MESH_H__
#define __MESH_H__

#include "globals.h"
#include "Output.h"
#include "Face.h"

class Mesh {
  IntVector freeVertices;
  VertexVector inside;
  VertexVector outside;
  TexCoordVector tc;
  FaceVector f;
  VertexVector v;
  VertexVector vbase;
  bool passable;
public:
  Mesh() : passable(false) {}
  int addVertex(Vertex vtx);
  inline Vertex getVertex( int vertexID ) const { 
    return v[vertexID]; 
  }
  inline void substituteVertex( int vertexID, Vertex vtx ) { 
    v[vertexID] = vtx; 
  }
  inline Face* getFace( int faceID ) { 
    return f[ faceID ];
  }
  inline void substituteFace( int faceID, Face* face ) { 
    f[ faceID ] = face;
  }
  inline void setPassable( ) {
    passable = true;
  }
  inline Vertex getFaceVertex( int faceID, int vertexID ) const { 
    return v[ f[ faceID ]->getVertex( vertexID ) ]; 
  }
  inline void addInsideVertex( Vertex vtx ) { 
    inside.push_back(vtx); 
  }
  int addTexCoord(TexCoord tcx);
  int addFace(Face* face) { f.push_back(face); return f.size()-1; }
  void extrudeFace(int fid, double amount, int mat = 0);
  IntVector* extrudeFaceR(int fid, double amount, int mat = 0);
  IntVector* splitFace(int fid, DoubleVector* splitData, bool horizontal, double ssnap = 0.0);
  void expandFace(int fid, double amount);
  Vertex faceNormal(int fid);
  Vertex faceCenter(int fid);
  IntVector* repeatSubdivdeFace(int fid, double snap, bool horizontal);
  void chamferFace(int fid, double amount);
  void taperFace(int fid, double amount);
  void scaleFace(int fid, double x, double y);
  void freeFace(int fid);
  void translateFace(int fid, double x, double y, double z);
  void weldVertices(int a, int b);
  void output(Output& out, int materialCount);
  void textureFace(int fid, double snap, double tile);
  void textureFaceFull(int fid);
  void textureFaceQuad(int fid, double au, double av, double bu, double bv);
  int createNGon(Vertex center, double radius, int n);
  inline Vertex getFaceEdge( int faceID, int id1, int id2 ) const { 
    return ( getFaceVertex( faceID, id2 ) - getFaceVertex( faceID, id1 ) ); 
  }
  inline double faceH( int faceID ) const { 
    return getFaceEdge( faceID, 1, 0 ).length(); 
  }
  inline double faceV( int faceID ) const { 
    return getFaceEdge( faceID, 0, 3 ).length(); 
  }
  String faceToString(Face* face);
  void pushBase(int fid);
  int rePushBase( );
  ~Mesh();
private:
  Vertex extensionVertex(int ida, int idb, int idc);
};

typedef std::vector<Mesh*> MeshVector;
typedef MeshVector::iterator MeshVectIter;

#endif /* __MESH_H__ */

// Local Variables: ***
// mode:C++ ***
// tab-width: 8 ***
// c-basic-offset: 2 ***
// indent-tabs-mode: t ***
// End: ***
// ex: shiftwidth=2 tabstop=8
