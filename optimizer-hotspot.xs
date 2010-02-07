#define PERL_NO_GET_CONTEXT
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include "ppport.h"

#ifndef MUTABLE_SV
#define MUTABLE_SV(ptr) ((SV*)ptr)
#endif


#define HOTSPOT 100

#define MY_CXT_KEY "optimizer::hotspot::_guts" XS_VERSION
typedef struct {
    Perl_check_t orig_ck_entersub;
    peep_t orig_peepp;

    I32 depth;

    U32 flags;
} my_cxt_t;
START_MY_CXT

void print_op(const OP* const o);
void
print_op(const OP* const o){
    if(!o){
        warn("[NULL]");
    }
    else if(o->op_type == OP_NULL){
        warn("[ex-%s]", PL_op_name[o->op_targ]);
    }
    else{
        warn("[%s]", PL_op_name[o->op_type]);
    }
}

/* safer version of cUNOPx(o)->op_first */
static OP*
op_first(OP* const o){
    if(!(o->op_flags & OPf_KIDS)){
        if(o->op_type == OP_NULL){
            croak("ex-%s has no kids", PL_op_name[o->op_targ]);
        }
        else{
            croak("%s has no kids", PL_op_name[o->op_type]);
        }
    }
    return cUNOPo->op_first;
}

static OP*
pp_optimized_gvav(pTHX) {
    dVAR;
    const I32 gimme = GIMME_V;
    SV* sv;
    AV* av;
    dSP;

    if(PL_op->op_private & OPpLVAL_INTRO){
        av = save_ary(cGVOP_gv);
        sv = MUTABLE_SV(av);
    }
    else{
        av = GvAVn(cGVOP_gv);
        sv = MUTABLE_SV(av);
    }

    //warn("[%"SVf"] %d", cGVOP_gv, (unsigned)PL_op->op_flags);

    if (PL_op->op_flags & OPf_REF) {
        XPUSHs(sv);
        RETURN;
    }
    else if (LVRET) {
        if (gimme != G_ARRAY){
            Perl_croak(aTHX_ "Can't return array to lvalue scalar context");
        }
        XPUSHs(sv);
        RETURN;
    }

    if (gimme == G_ARRAY) {
        const I32 maxarg = AvFILL(av) + 1;
        EXTEND(SP, maxarg);
        if (SvRMAGICAL(av)) {
            I32 i;
            for (i=0; i < maxarg; i++) {
                SV ** const svp = av_fetch(av, i, FALSE);
                /* See note in pp_helem, and bug id #27839 */
                SP[i+1] = svp
                    ? SvGMAGICAL(*svp) ? sv_mortalcopy(*svp) : *svp
                    : &PL_sv_undef;
            }
        }
        else {
            Copy(AvARRAY(av), SP+1, maxarg, SV*);
        }
        SP += maxarg;
    }
    else if (gimme == G_SCALAR) {
        mXPUSHi(AvFILL(av) + 1);
    }
    RETURN;
}

/* parameter assign */
static OP*
pp_optimized_passign(pTHX) {
    dVAR;
    OP* const rhs = cUNOP->op_first; // ex-list
    OP* const lhs = rhs->op_sibling;
    GV* const gv  = cGVOPx_gv(cUNOPx(cUNOPx(rhs)->op_first->op_sibling)->op_first);
    AV* const av  = GvAVn(gv);
    I32 const rmg = SvRMAGICAL(av);
    I32 const len = av_len(av) + 1;
    I32 i;
    OP* o;

    //warn("[%"SVf"]", gv);

    o = cUNOPx(lhs)->op_first;
    i = 0;

    for(o = o->op_sibling; o; o = o->op_sibling){
        SV* const targ = PAD_SVl(o->op_targ);

        if(o->op_private & OPpLVAL_INTRO){
            SAVECLEARSV(PAD_SVl(o->op_targ));
        }

        if(i < len){
            if(SvTYPE(targ) == SVt_PVAV){
                av_clear((AV*)targ);

                for(; i < len; i++){
                    SV** const valp = (rmg ? av_fetch(av, i, FALSE) : &(AvARRAY(av)[i]));
                    av_push((AV*)targ, valp ? newSVsv(*valp) : newSV(0));
                }
            }
            else{
                SV** const valp = (rmg ? av_fetch(av, i, FALSE) : &(AvARRAY(av)[i]));
                sv_setsv(targ, valp ? *valp : &PL_sv_undef);
                i++;
            }
        }
        else{ // clear targ
            if(SvTYPE(targ) == SVt_PVAV){
                av_clear((AV*)targ);
            }
            else{
                sv_setsv(targ, &PL_sv_undef);
            }
        }
        SvSETMAGIC(targ);
    }
    return NORMAL;
}

static void
optimizer_combine_opcode(pTHX_ OP* o){
    switch(o->op_type){
    case OP_GV:
    break;
    {
        OP* const op_next = o->op_next;
        if (op_next->op_type == OP_RV2AV
             && (op_next->op_flags & (OPf_WANT | OPf_REF)) != OPf_WANT_SCALAR
             && !(op_next->op_private & OPpDEREF)
            ) {

            op_null(op_next); /* nullize rv2av */

            o->op_private |= op_next->op_private;
            o->op_flags   |= op_next->op_flags & ~OPf_KIDS;

            o->op_next   = op_next->op_next;
            o->op_type   = OP_CUSTOM;
            o->op_ppaddr = pp_optimized_gvav;
        }
        break;
    }
    case OP_AASSIGN:{
        OP* kid;
        if(!((o->op_flags & OPf_WANT) == OPf_WANT_VOID)){
            return;
        }
        /*
            a  <@> leave[1 ref] vKP/REFC ->(end)
            1     <0> enter ->2
            2     <;> nextstate(main 1 -e:1) v:{ ->3
            9     <2> aassign[t5] vKS/COMMON ->a
            -        <1> ex-list lK ->6
            3           <0> pushmark s ->4
            5           <1> rv2av[t4] lK/1 ->6
            4              <#> gv[*_] s ->5
            -        <1> ex-list lKPRM/128 ->9
            6           <0> pushmark sRM/128 ->7
            7           <0> padsv[$a:1,2] lRM/LVINTRO ->8
            8           <0> padsv[$b:1,2] lRM/LVINTRO ->9
        */
        // Is right-hand side @_?
        kid = op_first(o);
        assert(kid->op_targ == OP_LIST); // ex-list

        kid = op_first(kid);
        assert(kid->op_type == OP_PUSHMARK);

        kid = kid->op_sibling; /* expect rv2av */
        assert(kid);

        if(kid->op_type == OP_RV2AV
            && op_first(kid)->op_type == OP_GV
            && kid->op_sibling == NULL
        ){
            kid = op_first(o)->op_sibling;
            assert(kid->op_targ == OP_LIST); // ex-list

            kid = op_first(kid);
            assert(kid->op_type == OP_PUSHMARK);

            for(kid = kid->op_sibling; kid; kid = kid->op_sibling){
                if(kid->op_private & (OPpPAD_STATE | OPpDEREF)){
                    return;
                }

                if(!(  kid->op_type == OP_PADSV
                    || kid->op_type == OP_PADAV
                )){
                    return;
                }
            }

            /* All right! */

            o->op_ppaddr = pp_optimized_passign;

            /* invalidate rhs's PUSHMARK */
            // XXX: use op_null()
            cUNOPx(cUNOPo->op_first)->op_first->op_ppaddr = PL_ppaddr[OP_NULL];
            cUNOPx(cUNOPo->op_first)->op_first->op_next   = o;

           // warn("optimize!");
        }
        break;
    }
    default:
        NOOP;
    }
}

static void
hotspot_peep(pTHX_ PTR_TBL_t* const seen, OP* o);

static void
hotspot_peep(pTHX_ PTR_TBL_t* const seen, OP* o){
    dVAR;
    for(; o; o = o->op_next){
        if(ptr_table_fetch(seen, o)){
            break;
        }
        ptr_table_store(seen, o, (void*)TRUE);

        /* apply this function recursively */
        switch(o->op_type){
        case OP_NEXTSTATE:
        case OP_DBSTATE:
            PL_curcop = cCOPo; /* for context info */
            break;

        case OP_MAPWHILE:
        case OP_GREPWHILE:
        case OP_AND:
        case OP_OR:
        case OP_DOR:
        case OP_ANDASSIGN:
        case OP_ORASSIGN:
        case OP_DORASSIGN:
        case OP_COND_EXPR:
        case OP_RANGE:
        case OP_ONCE:
            hotspot_peep(aTHX_ seen, cLOGOPo->op_other);
            break;
        case OP_ENTERLOOP:
        case OP_ENTERITER:
            hotspot_peep(aTHX_ seen, cLOOPo->op_redoop);
            hotspot_peep(aTHX_ seen, cLOOPo->op_nextop);
            hotspot_peep(aTHX_ seen, cLOOPo->op_lastop);
            break;
        case OP_SUBST:
            hotspot_peep(aTHX_ seen, cPMOPo->op_pmstashstartu.op_pmreplstart);
            break;

        default:
            NOOP;
        }

        optimizer_combine_opcode(aTHX_ o);
    }
}

static OP*
optimizer_pp_count(pTHX) {
    dVAR;
    OP* const o = PL_op;

    if(++o->op_private > HOTSPOT){
        COP* save_cop;
        OP* const op_start = o->op_sibling;
        PTR_TBL_t* seen;

        assert(op_start->op_next == o);

        //ENTER;
        //SAVEVPTR(PL_curcop);
        save_cop = PL_curcop;

        seen = ptr_table_new();

        hotspot_peep(aTHX_ seen, o->op_next);

        ptr_table_free(seen);

        /* free this opcode */
        op_start->op_next = o->op_next;
        PL_op = op_start;
        op_free(o);

        //LEAVE;
        PL_curcop = save_cop;
    }
    return NORMAL;
}

static void
optimizer_peep(pTHX_ OP* const o) {
    dMY_CXT;
    OP* op_count;

    assert(o->op_next->op_ppaddr != optimizer_pp_count);

    MY_CXT.orig_peepp(aTHX_ o);

    if(CvROOT(PL_compcv)){ // subroutines, rather than {map,grep,sort} blocks
        op_count = newOP(OP_CUSTOM, 0x00);
        op_count->op_ppaddr  = optimizer_pp_count;
        op_count->op_private = 0;

        op_count->op_sibling = o; // for retrival

        /* insert op_count */
        op_count->op_next = o->op_next;
        o->op_next        = op_count;
    }
}


MODULE = optimizer::hotspot        PACKAGE = optimizer::hotspot

PROTOTYPES: DISABLE

BOOT:
{
    MY_CXT_INIT;
    PERL_UNUSED_VAR(MY_CXT.depth);
}

void
import(klass)
CODE:
{
    dMY_CXT;
    if(MY_CXT.depth == 0){
        MY_CXT.orig_peepp = PL_peepp;
        PL_peepp          = optimizer_peep;
    }
    MY_CXT.depth++;
}


