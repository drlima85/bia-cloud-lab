import React from "react";
import { Link } from "react-router-dom";
import DadosHenrylle from "./DadosHenrylle.jsx";

const About = () => {
  return (
    <div className="about-page">
      <div className="about-content">
        <div className="feature-grid">
          <div className="feature-card highlight">
            <h3>Sobre o Projeto</h3>
            <h4>BIA Cloud Lab AWS</h4>
            <p>
              <strong>Desafio Labs 3.0 • Outubro/2026</strong>
              <br/>
              Laboratório prático com Docker, PostgreSQL
              e integração planejada com Redis/Valkey.
            </p>
          </div>
        </div>

        <DadosHenrylle />
      </div>

      <div className="about-footer">
        <Link to="/" className="back-button">
          ← Voltar
        </Link>
      </div>
    </div>
  );
};

export default About;
