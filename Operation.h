/* bzflag
 * Copyright (c) 1993 - 2006 Tim Riker
 *
 * This package is free software;  you can redistribute it and/or
 * modify it under the terms of the license found in the file
 * named COPYING that should have accompanied this file.
 *
 * THIS PACKAGE IS PROVIDED ``AS IS'' AND WITHOUT ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
 */

#ifndef __OPERATION_H__
#define __OPERATION_H__

#include <vector>
#include <string>
#include "Expression.h"
#include "Mesh.h"
#include "globals.h"

class Operation {
public:
  virtual int runMesh(Mesh*,int) = 0;
  virtual ~Operation() {}
};

typedef std::vector <Operation*> OperationVector;
typedef OperationVector::iterator OperationVectIter;

class RuleSet; // To avoid .h file recursion

class OperationNonterminal : public Operation {
  std::string ref;
  RuleSet* ruleset;
public:
  OperationNonterminal(std::string& _ref, RuleSet* _ruleset) : ref(_ref), ruleset(_ruleset) { };
  int runMesh(Mesh* mesh, int face);
};

class OperationSingle : public Operation {
protected:
  Expression *exp;
  float value;
public:
  OperationSingle(Expression* _exp) : exp(_exp) { };
  void flatten() { value = exp->calculate(); }
  ~OperationSingle() {
    delete exp;
  }
};


class OperationMaterial : public OperationSingle {
public:
  OperationMaterial(Expression* _exp) : OperationSingle(_exp) {}
  int runMesh(Mesh* mesh,int face) { 
    flatten();
    mesh->f[face]->mat = round(value);
    return face; 
  };
};

class OperationExpand : public OperationSingle {
public:
  OperationExpand(Expression* _exp) : OperationSingle(_exp) {}
  int runMesh(Mesh* mesh,int face) { 
    flatten();
    mesh->expandFace(face,value);
    return face; 
  };
};

class OperationMultifaces : public OperationSingle {
protected:
  StringVector* facerules;
  IntVector* faces;
  bool allsame;
public:
  OperationMultifaces(Expression* _exp, StringVector* _facerules) 
  : OperationSingle(_exp), facerules(_facerules), faces(NULL), allsame(false) {
    if (facerules != NULL) {
      if (facerules->size() == 0) {
        delete facerules; 
        facerules = NULL;
      } else
      if (facerules->size() == 1 && facerules->at(0)[0] == '@') {
        allsame = true;
        facerules->at(0).erase(0,1);
      }
    }
  }
  int runMesh(Mesh*,int) { 

    return 0;
  }
  ~OperationMultifaces() {
    if (facerules != NULL) delete facerules;
    if (faces != NULL) delete faces;
  }  
};

class OperationExtrude : public OperationMultifaces {
public:
  OperationExtrude(Expression* _exp, StringVector* facerules) : OperationMultifaces(_exp,facerules) {}
  int runMesh(Mesh* mesh,int face) { 
    flatten();
    if (facerules != NULL) {
      faces = mesh->extrudeFaceR(face,value,mesh->f[face]->mat);
      OperationMultifaces::runMesh(mesh,face);
    } else {
      mesh->extrudeFace(face,value,mesh->f[face]->mat);
    }
    return face; 
  };
};

class OperationSubdivide : public OperationMultifaces {
  bool horiz;
public:
  OperationSubdivide(Expression* _exp, bool _horiz, StringVector* facerules ) : OperationMultifaces(_exp,facerules), horiz(_horiz) {}
  int runMesh(Mesh* mesh,int face) { 
    flatten();
    faces = mesh->subdivdeFace(face,round(value),horiz);
    if (facerules == NULL) {
      delete faces;
      faces = NULL;
    } else {
      OperationMultifaces::runMesh(mesh,face);
    }
    return face; 
  };
};


#endif /* __OPERATION_H__ */

// Local Variables: ***
// mode:C++ ***
// tab-width: 8 ***
// c-basic-offset: 2 ***
// indent-tabs-mode: t ***
// End: ***
// ex: shiftwidth=2 tabstop=8
