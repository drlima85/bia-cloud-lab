import React from "react";

const DadosHenrylle = () => {
  const tecnologias = [
    {
      titulo: "Docker",
      descricao: "Containers e Docker Compose",
    },
    {
      titulo: "PostgreSQL",
      descricao: "Banco de dados e persistência",
    },
    {
      titulo: "Redis / Valkey",
      descricao: "Cache — implementação planejada",
    },
    {
      titulo: "AWS",
      descricao: "Infraestrutura cloud — próxima etapa",
    },
  ];

  return (
    <div className="dados-henrylle">
      <h3>Tecnologias do Laboratório</h3>

      <div className="links-grid">
        {tecnologias.map((tecnologia) => (
          <div className="link-card" key={tecnologia.titulo}>
            <h4>{tecnologia.titulo}</h4>
            <p>{tecnologia.descricao}</p>
          </div>
        ))}
      </div>
    </div>
  );
};

export default DadosHenrylle;
