#define PERL_NO_GET_CONTEXT
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include "ppport.h"

#ifndef MUTABLE_SV
#define MUTABLE_SV(ptr) ((SV*)ptr)
#endif

#define OPTIMIZE_ARGAV   0x000100
#define OPTIMIZE_PASSIGN 0x000200
#define OPTIMIZE_ALL     0xFFFF00

#define OPTIMIZE_TRACE   0x000001


#define HOTSPOT ((U8)100)

#define MY_CXT_KEY "optimizer::hotspot::_guts" XS_VERSION
typedef struct {
    Perl_check_t orig_ck_entersub;
    peep_t orig_peepp;

    I32 depth;

    UV flags;
} my_cxt_t;
START_MY_CXT

void print_op(const OP* const o); /* -W */
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

#define TRACE(name) STMT_START{ if(MY_CXT.flags & OPTIMIZE_TRACE) optimizer_trace(name); } STMT_END
static void
optimizer_trace(const char* const opname){
    dTHX;
    PerlIO_printf(Perl_debug_log, "#* %s (%s:%d)\n",
        opname, CopFILE(PL_curcop), (int)CopLINE(PL_curcop)
    );
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

/* @_ */
static OP*
pp_optimized_argav(pTHX) {
    dVAR;
    OP* o          = PL_op;
    const I32 want = o->op_flags & OPf_WANT;
    SV* sv;
    AV* av;
    dSP;

    assert(!LVRET);

    if(o->op_private & OPpLVAL_INTRO){
        av = save_ary(PL_defgv);
        sv = MUTABLE_SV(av);
    }
    else{
        av = GvAVn(PL_defgv);
        sv = MUTABLE_SV(av);
    }

    if (o->op_flags & OPf_REF) {
        XPUSHs(sv);
        RETURN;
    }

    if (want == OPf_WANT_LIST) {
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
    else if (want == OPf_WANT_SCALAR) {
        dTARGET;
        XPUSHi(AvFILL(av) + 1);
    }

    /* inline some simple ppcode */
    switch(o->op_next->op_type){
    case OP_PUSHMARK: {
        o = o->op_next;
        PUSHMARK(SP);
    }
    break;

    case OP_CONST: {
        o = o->op_next;
        XPUSHs(cSVOPo_sv);
    }
    break;

    default:
        //print_op(o->op_next); // for hints
        NOOP;
    }
    //print_op(o->op_next); // for hints
    PUTBACK;
    return o->op_next;
}

/* parameter assign */
static OP*
pp_optimized_passign(pTHX) {
    dVAR;
    OP* o         = PL_op;
    OP* const rhs = cUNOPo->op_first; // ex-list
    OP* const lhs = rhs->op_sibling;
    AV* const av  = GvAVn(PL_defgv);
    I32 const rmg = SvRMAGICAL(av);
    I32 const len = AvFILL(av) + 1;
    I32 i;

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

    /* because parameter assign is in statica void context,
       the next opcode will be nextstate.
    */
    o = PL_op->op_next;
    assert(o->op_type == OP_NEXTSTATE);

    /* pp_nextstate */
    {
        PL_curcop = cCOPo;
        TAINT_NOT;		/* Each statement is presumed innocent */
        PL_stack_sp = PL_stack_base + cxstack[cxstack_ix].blk_oldsp;
        /* no need to FREETMPS */
    }

    return o->op_next;
}

static void
optimizer_combine_opcode(pTHX_ pMY_CXT_ OP* o){
    switch(o->op_type){
    case OP_RV2AV:
    if(MY_CXT.flags & OPTIMIZE_ARGAV && o->op_ppaddr != pp_optimized_argav){
        OP* const op_gv = op_first(o);
        if (op_gv->op_type == OP_GV
             && cGVOPx_gv(op_gv) == PL_defgv
             && o->op_flags & OPf_WANT // must be in static context
            ) {

            o->op_ppaddr = pp_optimized_argav;

            op_null(op_gv);

            TRACE("argav");
        }
    }
    break;

    case OP_AASSIGN:
    if(MY_CXT.flags & OPTIMIZE_PASSIGN && o->op_ppaddr != pp_optimized_passign){
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

        kid = kid->op_sibling; /* expect argav */
        assert(kid);
        if(kid->op_ppaddr == pp_optimized_argav
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
            op_null(cUNOPx(cUNOPo->op_first)->op_first);
            cUNOPx(cUNOPo->op_first)->op_first->op_next = o;

            TRACE("passign");
        }
    }
    break;

    default:
        NOOP;
    }
}

static void
hotspot_peep(pTHX_ pMY_CXT_ PTR_TBL_t* const seen, OP* o);

static void
hotspot_peep(pTHX_ pMY_CXT_ PTR_TBL_t* const seen, OP* o){
    dVAR;
    for(; o; o = o->op_next){
        if(ptr_table_fetch(seen, o)){
            break;
        }
        ptr_table_store(seen, o, (void*)TRUE);

        optimizer_combine_opcode(aTHX_ aMY_CXT_ o);

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
            hotspot_peep(aTHX_ aMY_CXT_ seen, cLOGOPo->op_other);
            break;
        case OP_ENTERLOOP:
        case OP_ENTERITER:
            hotspot_peep(aTHX_ aMY_CXT_ seen, cLOOPo->op_redoop);
            hotspot_peep(aTHX_ aMY_CXT_ seen, cLOOPo->op_nextop);
            hotspot_peep(aTHX_ aMY_CXT_ seen, cLOOPo->op_lastop);
            break;
        case OP_SUBST:
            hotspot_peep(aTHX_ aMY_CXT_ seen, cPMOPo->op_pmstashstartu.op_pmreplstart);
            break;

        default:
            NOOP;
        }
    }
}

static OP*
optimizer_pp_count(pTHX) {
    dVAR;
    OP* const o = PL_op;

    if(++o->op_private > HOTSPOT){
        dMY_CXT;
        COP* save_cop;
        OP* const op_start = o->op_sibling;
        PTR_TBL_t* seen;

        assert(op_start->op_next == o);

        //ENTER;
        //SAVEVPTR(PL_curcop);
        save_cop = PL_curcop;

        seen = ptr_table_new();

        hotspot_peep(aTHX_ aMY_CXT_ seen, o->op_next);

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
    MY_CXT.flags = OPTIMIZE_ALL;
}

void
import(klass, SV* flags = NULL)
CODE:
{
    dMY_CXT;
    if(MY_CXT.depth == 0){
        MY_CXT.orig_peepp = PL_peepp;
        PL_peepp          = optimizer_peep;
    }
    MY_CXT.depth++;

    if(flags){
        if(SvPOK(flags)){
            STRLEN len;
            const char* const tmps = SvPV_const(flags, len);
            I32 grok_flags = PERL_SCAN_ALLOW_UNDERSCORES;

            MY_CXT.flags = grok_hex (tmps, &len, &grok_flags, NULL);
        }
        else{
            MY_CXT.flags = SvUV(flags);
        }
    }
}


